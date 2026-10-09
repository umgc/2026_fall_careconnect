package com.careconnect.controller.ehr;

import com.careconnect.model.ehr.MedicareEnvelope;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.model.ehr.MedicareSource;
import com.careconnect.model.ehr.MedicareStatusGate;
import com.careconnect.model.ehr.MockMedicareSource;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareRecordCache;
import com.careconnect.service.ehr.MedicareService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The Medicare reads with {@code careconnect.medicare.mode=mock}: served from the packaged fixtures
 * through the same status gate and envelope as live data, with no link and no call to Blue Button.
 * <p>
 * TC-MCR-API-010…030 are the IDs these cases had on {@code feature/e-medicare-mock-source}. 040 and 050
 * covered 503 paths that no longer exist, so they are not reused.
 */
@ExtendWith(MockitoExtension.class)
class EhrControllerMockModeTest {

    @Mock
    MedicareService medicareService;
    @Mock
    EhrService ehrService;
    @Mock
    MedicareRecordCache cache;
    @Mock
    ObjectProvider<MedicareSource> sources;

    private final MedicareProperties properties = new MedicareProperties();
    private EhrController controller;

    @BeforeEach
    void setUp() {
        controller = new EhrController();
        ReflectionTestUtils.setField(controller, "medicareService", medicareService);
        ReflectionTestUtils.setField(controller, "ehrService", ehrService);
        ReflectionTestUtils.setField(controller, "cache", cache);
        ReflectionTestUtils.setField(controller, "properties", properties);
        ReflectionTestUtils.setField(controller, "statusGate", new MedicareStatusGate());
        ReflectionTestUtils.setField(controller, "sources", sources);
    }

    private void mockMode() {
        ReflectionTestUtils.setField(properties, "mode", MedicareProperties.MODE_MOCK);
        when(sources.getIfAvailable()).thenReturn(new MockMedicareSource(new ObjectMapper()));
    }

    private static MedicareEnvelope envelope(final ResponseEntity<Object> response) {
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        return (MedicareEnvelope) response.getBody();
    }

    @Test
    @DisplayName("TC-MCR-API-010: the patient comes from the fixture, labelled mock and synthetic, with no link and no Blue Button call")
    void patientIsServedFromTheFixture() {
        mockMode();

        final MedicareEnvelope body = envelope(controller.fetchIdentity("medicare"));

        assertThat(body.source()).isEqualTo("MEDICARE");
        assertThat(body.mode()).isEqualTo("mock");
        assertThat(body.synthetic()).isTrue();
        assertThat(body.total()).isEqualTo(1);
        assertThat(body.resources().get(0).get("id").asText()).isEqualTo("-20140000008325");
        assertThat(body.fetchedAt()).as("fixtures are never retrieved from Medicare").isNull();
        verifyNoInteractions(medicareService, ehrService, cache);
    }

    @Test
    @DisplayName("TC-MCR-API-020: mock coverage goes through the status gate, so the cancelled Part D is not served")
    void coverageIsGated() {
        mockMode();

        final MedicareEnvelope body = envelope(controller.fetchCoverage("medicare"));

        assertThat(body.total()).isEqualTo(2);
        assertThat(body.resources())
                .extracting(c -> c.get("id").asText())
                .containsExactly("part-a--20140000008325", "part-b--20140000008325");
        assertThat(body.synthetic()).isTrue();
        verifyNoInteractions(medicareService, ehrService, cache);
    }

    @Test
    @DisplayName("TC-MCR-API-030: mock claims go through the status gate, so the entered-in-error claim is not served")
    void visitsAreGated() {
        mockMode();

        final MedicareEnvelope body = envelope(controller.fetchVisits("medicare"));

        assertThat(body.total()).isEqualTo(2);
        assertThat(body.resources())
                .extracting(v -> v.get("id").asText())
                .containsExactly("carrier--22639159481", "inpatient--4411138162");
        verifyNoInteractions(medicareService, ehrService, cache);
    }

    @Test
    @DisplayName("TC-MCR-API-060: in mock mode another source is still 404, and the fixtures are not consulted")
    void otherSourceIs404InMockMode() {
        ReflectionTestUtils.setField(properties, "mode", MedicareProperties.MODE_MOCK);

        assertThat(controller.fetchIdentity("epic").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchCoverage("epic").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(controller.fetchVisits("epic").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        verifyNoInteractions(sources, medicareService, ehrService, cache);
    }

    @Test
    @DisplayName("TC-MCR-API-070: in live mode the read needs a link, even if a mock source is registered")
    void liveModeIgnoresTheMockSource() {
        ReflectionTestUtils.setField(properties, "mode", MedicareProperties.MODE_LIVE);
        when(medicareService.getId()).thenReturn(7L);
        when(ehrService.getCrosswalk(7L)).thenReturn(Optional.empty());

        assertThat(controller.fetchCoverage("medicare").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        verify(sources, never()).getIfAvailable();
        verifyNoInteractions(cache);
    }
}
