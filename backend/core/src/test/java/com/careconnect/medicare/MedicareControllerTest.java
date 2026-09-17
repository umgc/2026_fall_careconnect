package com.careconnect.medicare;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/** TC-MCR-API: the three read endpoints, their envelope, and the disabled/unimplemented paths. */
@ExtendWith(MockitoExtension.class)
class MedicareControllerTest {

    @Mock
    private MedicareProperties properties;

    @Mock
    private ObjectProvider<MedicareSource> sources;

    private MedicareController controller;
    private MockMedicareSource mockSource;

    @BeforeEach
    void setUp() {
        controller = new MedicareController(properties, new MedicareResponseMapper(), sources);
        mockSource = new MockMedicareSource(new ObjectMapper(), new MedicareStatusGate());
    }

    private void givenEnabledMockSource() {
        when(properties.isEnabled()).thenReturn(true);
        when(properties.getMode()).thenReturn(MedicareProperties.MODE_MOCK);
        when(properties.isMock()).thenReturn(true);
        when(sources.getIfAvailable()).thenReturn(mockSource);
    }

    /** TC-MCR-API-010 */
    @Test
    void patient_whenMockSourceAvailable_returnsSingleResourceEnvelope() {
        givenEnabledMockSource();

        final ResponseEntity<Object> response = controller.patient();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        final MedicareEnvelope body = (MedicareEnvelope) response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.source()).isEqualTo("MEDICARE");
        assertThat(body.mode()).isEqualTo("mock");
        assertThat(body.synthetic()).isTrue();
        assertThat(body.total()).isEqualTo(1);
        assertThat(body.resources().get(0).get("id").asText()).isEqualTo("-20140000008325");
    }

    /** TC-MCR-API-020 */
    @Test
    void coverage_whenMockSourceAvailable_returnsGatedCoverage() {
        givenEnabledMockSource();

        final ResponseEntity<Object> response = controller.coverage();
        final MedicareEnvelope body = (MedicareEnvelope) response.getBody();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(body).isNotNull();
        assertThat(body.total()).isEqualTo(2);
        assertThat(body.resources()).hasSize(2);
    }

    /** TC-MCR-API-030 */
    @Test
    void visits_whenMockSourceAvailable_returnsGatedVisits() {
        givenEnabledMockSource();

        final ResponseEntity<Object> response = controller.visits();
        final MedicareEnvelope body = (MedicareEnvelope) response.getBody();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(body).isNotNull();
        assertThat(body.total()).isEqualTo(2);
    }

    /** TC-MCR-API-040: disabled environments answer 503, never an empty 200. */
    @Test
    void patient_whenDisabled_returnsServiceUnavailable() {
        when(properties.isEnabled()).thenReturn(false);

        final ResponseEntity<Object> response = controller.patient();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.get("error")).isEqualTo("medicare_unavailable");
        assertThat((String) body.get("detail")).contains("disabled");
    }

    /** TC-MCR-API-050: mode=live before a live source exists is a 503, not a startup failure. */
    @Test
    void coverage_whenModeHasNoRegisteredSource_returnsServiceUnavailable() {
        when(properties.isEnabled()).thenReturn(true);
        when(properties.getMode()).thenReturn(MedicareProperties.MODE_LIVE);
        when(sources.getIfAvailable()).thenReturn(null);

        final ResponseEntity<Object> response = controller.coverage();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).isNotNull();
        assertThat((String) body.get("detail")).contains("live");
    }

    /** TC-MCR-API-060: a source with no patient yields an empty envelope, not a null element. */
    @Test
    void patient_whenSourceHasNoPatient_returnsEmptyEnvelope() {
        when(properties.isEnabled()).thenReturn(true);
        when(properties.getMode()).thenReturn(MedicareProperties.MODE_MOCK);
        when(properties.isMock()).thenReturn(true);
        when(sources.getIfAvailable()).thenReturn(new EmptyMedicareSource());

        final ResponseEntity<Object> response = controller.patient();
        final MedicareEnvelope body = (MedicareEnvelope) response.getBody();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(body).isNotNull();
        assertThat(body.total()).isZero();
        assertThat(body.resources()).isEmpty();
    }

    /** A source that has nothing to return, for the empty-result path. */
    private static final class EmptyMedicareSource implements MedicareSource {
        @Override
        public String sourceCode() {
            return MedicareProperties.SOURCE_MEDICARE;
        }

        @Override
        public com.fasterxml.jackson.databind.JsonNode fetchPatient() {
            return null;
        }

        @Override
        public List<com.fasterxml.jackson.databind.JsonNode> fetchCoverage() {
            return List.of();
        }

        @Override
        public List<com.fasterxml.jackson.databind.JsonNode> fetchVisits() {
            return List.of();
        }
    }
}
