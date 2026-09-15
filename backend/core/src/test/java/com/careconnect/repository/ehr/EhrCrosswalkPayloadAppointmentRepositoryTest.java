package com.careconnect.repository.ehr;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.testsupport.fixtures.EhrFixtures;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * Persistence tests for the EHR patient crosswalk, raw payload, and appointment record tables
 * against the configured H2 test database (the test JDBC URL maps the PostgreSQL {@code jsonb}
 * domain to TEXT, so the raw payload round-trips).
 *
 * <p>NOTE: the unique indexes added in {@code 2609131500_ehr_crosswalk_payload_appointment.sql}
 * are applied by {@code SchemaPatchRunner} only under {@code isPostgreSql()}; they are verified
 * against a real PostgreSQL instance, not exercised here.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class EhrCrosswalkPayloadAppointmentRepositoryTest {

    @Autowired
    private EhrSourceRepository sourceRepository;

    @Autowired
    private EhrPatientCrosswalkRepository crosswalkRepository;

    @Autowired
    private EhrRawPayloadRepository rawPayloadRepository;

    @Autowired
    private EhrAppointmentRecordRepository appointmentRepository;

    @Autowired
    private PatientRepository patientRepository;

    private Patient patient;
    private EhrSource athenahealth;

    @BeforeEach
    void setUp() {
        patient = patientRepository.save(EhrFixtures.unsavedPatient());
        athenahealth = sourceRepository.save(EhrFixtures.athenahealthSource());
    }

    @Test
    void crosswalkResolvesTheExternalIdAnAdapterCallsTheSourceWith() {
        crosswalkRepository.save(EhrFixtures.crosswalk(patient, athenahealth));

        assertThat(crosswalkRepository.findByPatientIdAndSourceId(patient.getId(), athenahealth.getId()))
                .get()
                .extracting(EhrPatientCrosswalk::getExternalPatientId)
                .isEqualTo("a-12345");
    }

    @Test
    void crosswalkResolvesTheInternalPatientForAnInboundExternalId() {
        crosswalkRepository.save(EhrFixtures.crosswalk(patient, athenahealth));

        assertThat(crosswalkRepository.findBySourceIdAndExternalPatientId(athenahealth.getId(), "a-12345"))
                .get()
                .extracting(EhrPatientCrosswalk::getPatient)
                .extracting(Patient::getId)
                .isEqualTo(patient.getId());
    }

    @Test
    void rawPayloadRoundTripsJsonAndIsFoundByItsResourceKey() {
        final EhrRawPayload saved =
                rawPayloadRepository.save(EhrFixtures.rawAppointmentPayload(patient, athenahealth));

        assertThat(rawPayloadRepository.findById(saved.getId()))
                .get()
                .extracting(EhrRawPayload::getPayload)
                .satisfies(payload -> assertThat(payload).containsEntry("status", "booked"));

        assertThat(rawPayloadRepository
                .findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                        patient.getId(), athenahealth.getId(), "Appointment", "appt-1"))
                .isPresent();
    }

    @Test
    void appointmentRecordLinksBackToTheRawPayloadItWasMappedFrom() {
        final EhrRawPayload rawPayload =
                rawPayloadRepository.save(EhrFixtures.rawAppointmentPayload(patient, athenahealth));
        final EhrAppointmentRecord saved = appointmentRepository.save(
                EhrFixtures.appointment(patient, athenahealth, rawPayload));

        final EhrAppointmentRecord found =
                appointmentRepository.findById(saved.getId()).orElseThrow();
        assertThat(found.getRawPayload().getId()).isEqualTo(rawPayload.getId());
        assertThat(found.getStatus()).isEqualTo("booked");
    }

    @Test
    void appointmentUpsertKeyFindsTheExistingRowInsteadOfDuplicating() {
        final EhrRawPayload rawPayload =
                rawPayloadRepository.save(EhrFixtures.rawAppointmentPayload(patient, athenahealth));
        appointmentRepository.save(EhrFixtures.appointment(patient, athenahealth, rawPayload));

        assertThat(appointmentRepository.findByPatientIdAndSourceIdAndExternalAppointmentId(
                        patient.getId(), athenahealth.getId(), "appt-1"))
                .isPresent();
        assertThat(appointmentRepository.findByPatientIdAndSourceIdAndExternalAppointmentId(
                        patient.getId(), athenahealth.getId(), "does-not-exist"))
                .isEmpty();
    }
}
