package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.careconnect.config.CernerProperties;
import com.careconnect.integration.cerner.CernerAllergyMapper.Allergy;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CernerAllergyServiceTest {

    @Mock
    private CernerAllergyService delegate;

    private CernerAllergyServiceImpl service;

    @BeforeEach
    void setUp() {
        service = new CernerAllergyServiceImpl(delegate);
    }

    @Test
    void getAllergiesRejectsNonPositivePatientId() {
        assertThatThrownBy(() -> service.getAllergies(0L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("patientId must be positive");
        verifyNoInteractions(delegate);
    }

    @Test
    void getAllergiesReusesAuthenticatedAllergyIntoleranceBundleTransport() throws Exception {
        final String bundle = """
                {
                  "resourceType": "Bundle",
                  "type": "searchset",
                  "entry": [
                    {
                      "resource": {
                        "resourceType": "AllergyIntolerance",
                        "id": "allergy-101",
                        "patient": { "reference": "Patient/cerner-patient-42" },
                        "clinicalStatus": {
                          "coding": [{ "code": "active" }]
                        },
                        "verificationStatus": {
                          "coding": [{ "code": "confirmed" }]
                        },
                        "code": {
                          "text": "Penicillin"
                        }
                      }
                    }
                  ]
                }
                """;

        final AtomicReference<String> observedAuthHeader = new AtomicReference<>();
        final AtomicReference<String> observedPath = new AtomicReference<>();
        final HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/fhir/AllergyIntolerance", exchange -> {
            observedAuthHeader.set(exchange.getRequestHeaders().getFirst("Authorization"));
            observedPath.set(exchange.getRequestURI().toString());
            final byte[] body = bundle.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/fhir+json");
            exchange.sendResponseHeaders(200, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();

        try {
            final URI base = URI.create(
                    "http://127.0.0.1:" + server.getAddress().getPort() + "/fhir/");
            final CernerAllergyHttpClient httpClient =
                    new CernerAllergyHttpClient(base, Duration.ofSeconds(2));

            final PatientRepository patients = mock(PatientRepository.class);
            final EhrSourceRepository sources = mock(EhrSourceRepository.class);
            final EhrPatientCrosswalkRepository crosswalks =
                    mock(EhrPatientCrosswalkRepository.class);
            final EhrRawPayloadRepository rawPayloads = mock(EhrRawPayloadRepository.class);
            final CernerOAuthService oauth = mock(CernerOAuthService.class);
            final Clock clock =
                    Clock.fixed(Instant.parse("2026-10-30T12:00:00Z"), ZoneOffset.UTC);

            final User user = new User();
            user.setId(7L);
            final Patient patient = new Patient();
            patient.setId(42L);
            patient.setUser(user);

            final EhrSource source = new EhrSource();
            source.setId(3L);
            source.setCode(CernerProperties.SOURCE_ORACLE_HEALTH);

            final EhrPatientCrosswalk crosswalk = new EhrPatientCrosswalk();
            crosswalk.setPatientId(42L);
            crosswalk.setSourceId(3L);
            crosswalk.setExternalPatientId("cerner-patient-42");

            when(patients.findById(42L)).thenReturn(Optional.of(patient));
            when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH))
                    .thenReturn(Optional.of(source));
            when(crosswalks.findByPatientIdAndSourceId(42L, 3L))
                    .thenReturn(Optional.of(crosswalk));
            when(oauth.patientFhirId(7L)).thenReturn("Patient/cerner-patient-42");
            when(oauth.validAccessToken(7L)).thenReturn("authenticated-oauth-token");
            when(rawPayloads.save(any(EhrRawPayload.class)))
                    .thenAnswer(inv -> inv.getArgument(0));

            final CernerAllergyServiceImpl authenticatedService = new CernerAllergyServiceImpl(
                    patients, sources, crosswalks, rawPayloads, oauth, httpClient, clock);

            final List<Allergy> result = authenticatedService.getAllergies(42L);

            assertThat(observedAuthHeader.get()).isEqualTo("Bearer authenticated-oauth-token");
            assertThat(observedPath.get())
                    .isEqualTo("/fhir/AllergyIntolerance?patient=cerner-patient-42");
            assertThat(result).hasSize(1);
            assertThat(result.get(0).sourceRecordId()).isEqualTo("allergy-101");
            assertThat(result.get(0).substanceText()).isEqualTo("Penicillin");
            verify(rawPayloads).save(any(EhrRawPayload.class));
        } finally {
            server.stop(0);
        }
    }

    @Test
    void getAllergiesPropagatesUnknownPatientException() {
        when(delegate.getAllergies(42L))
                .thenThrow(new CernerAllergyService.UnknownPatientException());

        assertThatThrownBy(() -> service.getAllergies(42L))
                .isInstanceOf(CernerAllergyService.UnknownPatientException.class);
    }

    @Test
    void getAllergiesPropagatesCernerSourceException() {
        final CernerAllergyService.CernerSourceException upstream =
                new CernerAllergyService.CernerSourceException("CERNER_AUTH_EXPIRED", false);
        when(delegate.getAllergies(42L)).thenThrow(upstream);

        assertThatThrownBy(() -> service.getAllergies(42L)).isSameAs(upstream);
    }

    @Test
    void getAllergiesWrapsUnexpectedRuntimeException() {
        when(delegate.getAllergies(42L)).thenThrow(new IllegalStateException("boom"));

        assertThatThrownBy(() -> service.getAllergies(42L))
                .isInstanceOf(CernerAllergyService.CernerSourceException.class)
                .extracting(ex -> ((CernerAllergyService.CernerSourceException) ex).code())
                .isEqualTo("CERNER_SOURCE_UNAVAILABLE");
    }
}
