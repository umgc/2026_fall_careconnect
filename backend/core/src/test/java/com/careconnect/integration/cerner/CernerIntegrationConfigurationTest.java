package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.careconnect.config.CernerProperties;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class CernerIntegrationConfigurationTest {

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
}
