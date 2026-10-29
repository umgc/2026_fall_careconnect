package com.careconnect.integration.cerner;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.equalTo;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrConditionRecordRepository;
import com.careconnect.repository.ehr.EhrEncounterRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.stubbing.Scenario;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

/** Spring-managed service-to-HTTP integration tests against a real WireMock server. */
@SpringBootTest(
        classes = CernerConditionEncounterWireMockIntegrationTest.TestApplication.class,
        properties = "careconnect.cerner.enabled=true")
class CernerConditionEncounterWireMockIntegrationTest {

    private static final WireMockServer WIREMOCK = new WireMockServer(0);

    static {
        WIREMOCK.start();
    }

    @Autowired private CernerConditionEncounterService service;

    @MockitoBean private PatientRepository patients;
    @MockitoBean private EhrSourceRepository sources;
    @MockitoBean private EhrPatientCrosswalkRepository crosswalks;
    @MockitoBean private EhrRawPayloadRepository rawPayloads;
    @MockitoBean private EhrConditionRecordRepository conditions;
    @MockitoBean private EhrEncounterRecordRepository encounters;
    @MockitoBean private CernerOAuthService oauth;

    @BeforeEach
    void setUp() {
        WIREMOCK.resetAll();
        final Patient patient = Patient.builder()
                .id(42L)
                .user(User.builder().id(77L).build())
                .build();
        final EhrSource source = EhrSource.builder()
                .id(5L)
                .code(CernerProperties.SOURCE_ORACLE_HEALTH)
                .build();
        when(patients.findById(42L)).thenReturn(Optional.of(patient));
        when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH))
                .thenReturn(Optional.of(source));
        when(crosswalks.findByPatientIdAndSourceId(42L, 5L)).thenReturn(Optional.of(
                EhrPatientCrosswalk.builder()
                        .patientId(42L)
                        .sourceId(5L)
                        .externalPatientId("synthetic-patient-1")
                        .build()));
        when(oauth.patientFhirId(77L)).thenReturn("Patient/synthetic-patient-1");
        when(oauth.validAccessToken(77L)).thenReturn("access-token");
        when(rawPayloads.findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                any(), any(), any(), any())).thenReturn(Optional.empty());
        when(rawPayloads.save(any())).thenAnswer(invocation -> {
            final EhrRawPayload raw = invocation.getArgument(0);
            raw.setId(101L);
            return raw;
        });
        when(conditions.findByPatientIdAndSourceIdAndExternalConditionId(
                any(), any(), any())).thenReturn(Optional.empty());
        when(conditions.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
    }

    @AfterAll
    static void stopWireMock() {
        WIREMOCK.stop();
    }

    @Test
    @Tag("M3-REQ-17")
    void conditionHappyPathTraversesSpringServiceHttpMappingRawAndCanonicalLayers()
            throws Exception {
        WIREMOCK.stubFor(get(urlPathEqualTo("/fhir/Condition"))
                .withQueryParam("patient", equalTo("synthetic-patient-1"))
                .withHeader("Authorization", equalTo("Bearer access-token"))
                .willReturn(okJson(fixture(
                        "/cerner/fhir/condition/bundle-one-condition.json"))));

        final var records = service.synchronizeConditions(42L);

        assertThat(records).singleElement().satisfies(record -> {
            assertThat(record.getExternalConditionId()).isEqualTo("synthetic-condition-1");
            assertThat(record.getRawPayloadId()).isEqualTo(101L);
            assertThat(record.getConditionText()).isEqualTo("Synthetic hypertension");
        });
        verify(rawPayloads).save(any(EhrRawPayload.class));
        verify(conditions).save(any());
        WIREMOCK.verify(1, getRequestedFor(urlPathEqualTo("/fhir/Condition")));
    }

    @Test
    @Tag("M3-REQ-09")
    void upstream401RefreshesOnceAndRetriesThroughSpringManagedService() {
        WIREMOCK.stubFor(get(urlPathEqualTo("/fhir/Encounter"))
                .inScenario("refresh")
                .whenScenarioStateIs(Scenario.STARTED)
                .withHeader("Authorization", equalTo("Bearer access-token"))
                .willReturn(aResponse().withStatus(401))
                .willSetStateTo("refreshed"));
        WIREMOCK.stubFor(get(urlPathEqualTo("/fhir/Encounter"))
                .inScenario("refresh")
                .whenScenarioStateIs("refreshed")
                .withHeader("Authorization", equalTo("Bearer fresh-token"))
                .willReturn(okJson(
                        "{\"resourceType\":\"Bundle\",\"type\":\"searchset\","
                                + "\"entry\":[]}")));
        when(oauth.refreshAccessToken(77L)).thenReturn("fresh-token");

        assertThat(service.synchronizeEncounters(42L)).isEmpty();

        verify(oauth).refreshAccessToken(77L);
        WIREMOCK.verify(2, getRequestedFor(urlPathEqualTo("/fhir/Encounter")));
    }

    private String fixture(final String path) throws Exception {
        try (var input = getClass().getResourceAsStream(path)) {
            assertThat(input).isNotNull();
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    @Configuration(proxyBeanMethods = false)
    @EnableAutoConfiguration(exclude = {
            DataSourceAutoConfiguration.class,
            HibernateJpaAutoConfiguration.class
    })
    @Import(DefaultCernerConditionEncounterService.class)
    static class TestApplication {

        @Bean
        CernerFhirBundleHttpClient cernerFhirBundleHttpClient() {
            return new CernerFhirBundleHttpClient(
                    URI.create(WIREMOCK.baseUrl() + "/fhir/"), Duration.ofSeconds(1));
        }

        @Bean
        Clock clock() {
            return Clock.fixed(Instant.parse("2026-10-21T12:00:00Z"), ZoneOffset.UTC);
        }
    }
}
