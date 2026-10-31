package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.careconnect.config.CernerProperties;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.EhrAppointmentRecordRepository;
import com.careconnect.repository.ehr.EhrConditionRecordRepository;
import com.careconnect.repository.ehr.EhrEncounterRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.ehr.CernerOAuthService;
import java.time.Clock;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.convert.ApplicationConversionService;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.FilterType;

class CernerIntegrationConfigurationTest {

    @Configuration
    @ComponentScan(
            basePackageClasses = CernerIntegrationConfiguration.class,
            excludeFilters = @ComponentScan.Filter(
                    type = FilterType.REGEX,
                    pattern = ".*Test.*"))
    static class CernerPackageScanConfiguration { }

    private final CernerProperties properties = mock(CernerProperties.class);
    private final CernerIntegrationConfiguration configuration =
            new CernerIntegrationConfiguration();

    @BeforeEach
    void configureTimeout() {
        when(properties.getHttpTimeout()).thenReturn(Duration.ofSeconds(2));
    }

    @Test
    void createsBothClientsAndNormalizesMissingTrailingSlash() {
        when(properties.getFhirBaseUrl()).thenReturn("https://example.test/fhir");

        assertThat(configuration.cernerAllergyHttpClient(properties)).isNotNull();
        assertThat(configuration.cernerFhirBundleHttpClient(properties)).isNotNull();
    }

    @Test
    void rejectsMissingFhirBaseForBothClients() {
        when(properties.getFhirBaseUrl()).thenReturn(" ");

        assertThatThrownBy(() -> configuration.cernerAllergyHttpClient(properties))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("cerner.oauth.fhir-base-url is required");
        assertThatThrownBy(() -> configuration.cernerFhirBundleHttpClient(properties))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("cerner.oauth.fhir-base-url is required");
    }

    @Test
    void enablingCernerRegistersUniqueServiceBeansWithoutAmbiguity() {
        new ApplicationContextRunner()
                .withInitializer(ctx -> ctx.getBeanFactory()
                        .setConversionService(ApplicationConversionService.getSharedInstance()))
                .withUserConfiguration(
                        CernerProperties.class,
                        CernerPackageScanConfiguration.class)
                .withBean(UserRepository.class, () -> mock(UserRepository.class))
                .withBean(PatientRepository.class, () -> mock(PatientRepository.class))
                .withBean(AuthorizationService.class, () -> mock(AuthorizationService.class))
                .withBean(EhrSourceRepository.class, () -> mock(EhrSourceRepository.class))
                .withBean(EhrPatientCrosswalkRepository.class,
                        () -> mock(EhrPatientCrosswalkRepository.class))
                .withBean(EhrRawPayloadRepository.class, () -> mock(EhrRawPayloadRepository.class))
                .withBean(EhrSourceIdentityRepository.class,
                        () -> mock(EhrSourceIdentityRepository.class))
                .withBean(EhrAppointmentRecordRepository.class,
                        () -> mock(EhrAppointmentRecordRepository.class))
                .withBean(EhrConditionRecordRepository.class,
                        () -> mock(EhrConditionRecordRepository.class))
                .withBean(EhrEncounterRecordRepository.class,
                        () -> mock(EhrEncounterRecordRepository.class))
                .withBean(CernerOAuthService.class, () -> mock(CernerOAuthService.class))
                .withBean(Clock.class, Clock::systemUTC)
                .withPropertyValues(
                        "careconnect.cerner.enabled=true",
                        "careconnect.cerner.allergies.enabled=true",
                        "careconnect.cerner.patient-appointment.enabled=true",
                        "careconnect.cerner.clinical.enabled=true",
                        "cerner.oauth.fhir-base-url=https://example.test/fhir/")
                .run(context -> {
                    assertThat(context).hasNotFailed();
                    assertThat(context).hasSingleBean(CernerPatientAppointmentService.class);
                    assertThat(context.getBean(CernerPatientAppointmentService.class))
                            .isInstanceOf(DefaultCernerPatientAppointmentService.class);
                    assertThat(context).hasSingleBean(CernerAllergyService.class);
                    assertThat(context.getBean(CernerAllergyService.class))
                            .isInstanceOf(DefaultCernerAllergyService.class);
                    assertThat(context).hasSingleBean(CernerConditionEncounterService.class);
                    assertThat(context).hasSingleBean(CernerAccessPolicy.class);
                    assertThat(context).hasSingleBean(CernerAllergyController.class);
                    assertThat(context).hasSingleBean(CernerPatientAppointmentController.class);
                    assertThat(context).hasSingleBean(CernerClinicalController.class);
                });
    }
}
