package com.careconnect.model.ehr;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The fixture-backed source behind {@code careconnect.medicare.mode=mock}. Runs against the packaged
 * fixtures rather than inline JSON, because the point is that what ships on the classpath parses.
 * <p>
 * TC-MCR-MOCK-010…060 are the IDs these cases had on {@code feature/e-medicare-mock-source}; 030 and 040
 * now check that the blocked resources ship, since the status gate moved to {@code EhrController}
 * (TC-MCR-API-020/030 check that it drops them).
 */
class MockMedicareSourceTest {

    private MockMedicareSource source;

    @BeforeEach
    void setUp() {
        source = new MockMedicareSource(new ObjectMapper());
    }

    @Test
    @DisplayName("TC-MCR-MOCK-010: the source code is MEDICARE")
    void sourceCodeIsMedicare() {
        assertThat(source.sourceCode()).isEqualTo("MEDICARE");
    }

    @Test
    @DisplayName("TC-MCR-MOCK-020: the patient is the synthetic beneficiary from the fixture")
    void patientComesFromTheFixture() {
        final JsonNode patient = source.fetchPatient();

        assertThat(patient).isNotNull();
        assertThat(patient.get("resourceType").asText()).isEqualTo("Patient");
        assertThat(patient.get("id").asText()).isEqualTo("-20140000008325");
        assertThat(patient.get("birthDate").asText()).isEqualTo("1940-06-01");
    }

    @Test
    @DisplayName("TC-MCR-MOCK-030: all three Coverage resources ship as Blue Button sends them, including the cancelled Part D")
    void coverageShipsEveryEntry() {
        assertThat(source.fetchCoverage())
                .extracting(c -> c.get("id").asText() + "/" + c.get("status").asText())
                .containsExactly(
                        "part-a--20140000008325/active",
                        "part-b--20140000008325/active",
                        "part-d--20140000008325/cancelled");
    }

    @Test
    @DisplayName("TC-MCR-MOCK-040: all three claims ship as Blue Button sends them, including the entered-in-error one")
    void visitsShipEveryEntry() {
        assertThat(source.fetchVisits())
                .extracting(v -> v.get("id").asText() + "/" + v.get("status").asText())
                .containsExactly(
                        "carrier--22639159481/active",
                        "inpatient--4411138162/active",
                        "carrier--22639159999/entered-in-error");
    }

    @Test
    @DisplayName("TC-MCR-MOCK-050: diagnosis and procedure codes survive as CodeableConcepts")
    void codesSurviveAsCodeableConcepts() {
        final JsonNode carrier = source.fetchVisits().get(0);

        final JsonNode diagnosis = carrier.get("diagnosis").get(0).get("diagnosisCodeableConcept").get("coding").get(0);
        assertThat(diagnosis.get("system").asText()).isEqualTo("http://hl7.org/fhir/sid/icd-10-cm");
        assertThat(diagnosis.get("code").asText()).isEqualTo("I10");

        final JsonNode service = carrier.get("item").get(0).get("productOrService").get("coding").get(0);
        assertThat(service.get("code").asText()).isEqualTo("99214");
    }

    @Test
    @DisplayName("TC-MCR-MOCK-060: callers cannot change the loaded fixtures")
    void fetchedListsAreImmutable() {
        final List<JsonNode> coverage = source.fetchCoverage();
        final List<JsonNode> visits = source.fetchVisits();

        assertThatThrownBy(() -> coverage.add(null)).isInstanceOf(UnsupportedOperationException.class);
        assertThatThrownBy(() -> visits.add(null)).isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    @DisplayName("TC-MCR-MOCK-070: the source is registered in mock mode, or with no mode set, and never in live mode")
    void registeredOnlyInMockMode() {
        final ApplicationContextRunner runner = new ApplicationContextRunner()
                .withBean(ObjectMapper.class, ObjectMapper::new)
                .withUserConfiguration(MockMedicareSource.class);

        runner.withPropertyValues("careconnect.medicare.mode=mock")
                .run(context -> assertThat(context).hasSingleBean(MedicareSource.class));
        runner.withPropertyValues("careconnect.medicare.mode=MOCK")
                .run(context -> assertThat(context).hasSingleBean(MedicareSource.class));
        runner.run(context -> assertThat(context).hasSingleBean(MedicareSource.class));
        runner.withPropertyValues("careconnect.medicare.mode=live")
                .run(context -> assertThat(context).doesNotHaveBean(MedicareSource.class));
    }
}
