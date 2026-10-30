package com.careconnect.integration.cerner;

import com.careconnect.integration.cerner.CernerAllergyMapper.Allergy;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.MockedStatic;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class CernerAllergyServiceTest {

    @Mock
    private CernerPatientAppointmentService patientAppointmentService;

    @Mock
    private CernerFhirBundleHttpClient fhirClient;

    private CernerAllergyServiceImpl service;

    private static final ObjectMapper JSON = new ObjectMapper();

    @BeforeEach
    void setUp() {
        service = new CernerAllergyServiceImpl(patientAppointmentService, fhirClient);
    }

    @Test
    void getAllergiesRejectsNonPositivePatientId() {
        assertThatThrownBy(() -> service.getAllergies(0L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("patientId must be positive");
    }

    @Test
    void getAllergiesReturnsMappedAllergies() throws Exception {
        JsonNode bundle = JSON.readTree("""
            {
              "resourceType":"Bundle",
              "type":"searchset",
              "entry":[
                {
                  "resource":{
                    "resourceType":"AllergyIntolerance",
                    "id":"a1",
                    "patient":{"reference":"Patient/42"}
                  }
                }
              ]
            }
            """);

        when(patientAppointmentService.validatePatientAndAppointmentExpectedOutputFixtures(
                eq(42L), any(Instant.class), any(Instant.class)))
                .thenReturn(true);
        when(fhirClient.getAllergies("42")).thenReturn(bundle);

        List<Allergy> expected = List.of(
                new Allergy("ORACLE_HEALTH", "a1", null, null, null, null, null, null, List.of())
        );

        try (MockedStatic<CernerAllergyMapper> mapper = mockStatic(CernerAllergyMapper.class)) {
            mapper.when(() -> CernerAllergyMapper.map(bundle, "42")).thenReturn(expected);

            List<Allergy> out = service.getAllergies(42L);

            assertThat(out).isEqualTo(expected);
            mapper.verify(() -> CernerAllergyMapper.map(bundle, "42"));
        }

        verify(fhirClient).getAllergies("42");
    }

    @Test
    void getAllergiesPropagatesUnknownPatientException() {
        when(patientAppointmentService.validatePatientAndAppointmentExpectedOutputFixtures(
                eq(42L), any(Instant.class), any(Instant.class)))
                .thenReturn(false);

        assertThatThrownBy(() -> service.getAllergies(42L))
                .isInstanceOf(CernerAllergyService.UnknownPatientException.class);

        verifyNoInteractions(fhirClient);
    }

    @Test
    void getAllergiesPropagatesCernerSourceException() {
        when(patientAppointmentService.validatePatientAndAppointmentExpectedOutputFixtures(
                eq(42L), any(Instant.class), any(Instant.class)))
                .thenReturn(true);

        CernerAllergyService.CernerSourceException upstream =
                new CernerAllergyService.CernerSourceException("CERNER_AUTH_EXPIRED", false);

        when(fhirClient.getAllergies("42")).thenThrow(upstream);

        assertThatThrownBy(() -> service.getAllergies(42L))
                .isSameAs(upstream);
    }

    @Test
    void getAllergiesWrapsUnexpectedException() {
        when(patientAppointmentService.validatePatientAndAppointmentExpectedOutputFixtures(
                eq(42L), any(Instant.class), any(Instant.class)))
                .thenReturn(true);
        when(fhirClient.getAllergies("42")).thenThrow(new RuntimeException("boom"));

        assertThatThrownBy(() -> service.getAllergies(42L))
                .isInstanceOf(CernerAllergyService.CernerSourceException.class)
                .extracting(ex -> ((CernerAllergyService.CernerSourceException) ex).code())
                .isEqualTo("CERNER_SOURCE_UNAVAILABLE");
    }
}
