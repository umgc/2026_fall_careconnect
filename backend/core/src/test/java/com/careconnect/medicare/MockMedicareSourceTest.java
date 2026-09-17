package com.careconnect.medicare;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * TC-MCR-MOCK: the fixture-backed source reads the packaged Blue Button Bundles the same way the
 * live client will, and the status gate is applied on the way out.
 *
 * <p>Deliberately runs against the real fixtures rather than inline JSON: the point of these
 * tests is that what ships on the classpath parses and survives the gate.
 */
class MockMedicareSourceTest {

    private MockMedicareSource source;

    @BeforeEach
    void setUp() {
        source = new MockMedicareSource(new ObjectMapper(), new MedicareStatusGate());
    }

    /** TC-MCR-MOCK-010 */
    @Test
    void sourceCode_isMedicare() {
        assertThat(source.sourceCode()).isEqualTo("MEDICARE");
    }

    /** TC-MCR-MOCK-020 */
    @Test
    void fetchPatient_returnsTheBeneficiaryFromTheFixture() {
        final JsonNode patient = source.fetchPatient();

        assertThat(patient).isNotNull();
        assertThat(patient.get("resourceType").asText()).isEqualTo("Patient");
        assertThat(patient.get("id").asText()).isEqualTo("-20140000008325");
        assertThat(patient.get("birthDate").asText()).isEqualTo("1940-06-01");
    }

    /** TC-MCR-MOCK-030: three Coverage entries ship, the cancelled Part D is gated out. */
    @Test
    void fetchCoverage_dropsCancelledCoverage() {
        final List<JsonNode> coverage = source.fetchCoverage();

        assertThat(coverage).hasSize(2);
        assertThat(coverage).allSatisfy(c -> assertThat(c.get("status").asText()).isEqualTo("active"));
        assertThat(coverage)
                .extracting(c -> c.get("id").asText())
                .containsExactly("part-a--20140000008325", "part-b--20140000008325");
    }

    /** TC-MCR-MOCK-040: three EOB entries ship, the entered-in-error claim is gated out. */
    @Test
    void fetchVisits_dropsEnteredInErrorClaims() {
        final List<JsonNode> visits = source.fetchVisits();

        assertThat(visits).hasSize(2);
        assertThat(visits)
                .extracting(v -> v.get("id").asText())
                .containsExactly("carrier--22639159481", "inpatient--4411138162");
        assertThat(visits)
                .noneSatisfy(v -> assertThat(v.get("status").asText()).isEqualTo("entered-in-error"));
    }

    /** TC-MCR-MOCK-050: diagnosis and procedure codes survive retrieval as CodeableConcepts. */
    @Test
    void fetchVisits_preservesCodeableConceptCodes() {
        final JsonNode carrier = source.fetchVisits().get(0);

        final JsonNode diagnosis =
                carrier.get("diagnosis").get(0).get("diagnosisCodeableConcept").get("coding").get(0);
        assertThat(diagnosis.get("system").asText()).isEqualTo("http://hl7.org/fhir/sid/icd-10-cm");
        assertThat(diagnosis.get("code").asText()).isEqualTo("I10");

        final JsonNode service = carrier.get("item").get(0).get("productOrService").get("coding").get(0);
        assertThat(service.get("code").asText()).isEqualTo("99214");
    }

    /** TC-MCR-MOCK-060: callers cannot mutate the cached fixture state. */
    @Test
    void fetchedCollections_areImmutable() {
        assertThatThrownBy(() -> source.fetchCoverage().add(null))
                .isInstanceOf(UnsupportedOperationException.class);
        assertThatThrownBy(() -> source.fetchVisits().add(null))
                .isInstanceOf(UnsupportedOperationException.class);
    }
}
