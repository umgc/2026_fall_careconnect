package com.careconnect.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class EpicPropertiesTest {

    @Test
    void exposesConfiguredValuesAndDetectsConfidentialClient() {
        final EpicProperties properties = new EpicProperties();
        ReflectionTestUtils.setField(properties, "enabled", true);
        ReflectionTestUtils.setField(properties, "fhirBaseUrl", "https://example.test/fhir/");
        ReflectionTestUtils.setField(properties, "clientId", "client-id");
        ReflectionTestUtils.setField(properties, "clientSecret", "secret");
        ReflectionTestUtils.setField(properties, "redirectUri", "https://app.test/callback");
        ReflectionTestUtils.setField(properties, "scopes",
                "openid patient/Patient.read patient/Appointment.read");
        ReflectionTestUtils.setField(properties, "appReturnDeepLink", "careconnect://epic/linked");
        ReflectionTestUtils.setField(properties, "webReturnUrl", "https://app.test/#/epic-linked");
        ReflectionTestUtils.setField(properties, "deltaSafetyMarginHours", 24L);
        ReflectionTestUtils.setField(properties, "diagnosticsVerbose", true);

        assertThat(properties.isEnabled()).isTrue();
        assertThat(properties.getFhirBaseUrl()).isEqualTo("https://example.test/fhir/");
        assertThat(properties.getClientId()).isEqualTo("client-id");
        assertThat(properties.getClientSecret()).isEqualTo("secret");
        assertThat(properties.getRedirectUri()).isEqualTo("https://app.test/callback");
        assertThat(properties.getScopes()).contains("patient/Patient.read", "patient/Appointment.read");
        assertThat(properties.getAppReturnDeepLink()).isEqualTo("careconnect://epic/linked");
        assertThat(properties.getWebReturnUrl()).isEqualTo("https://app.test/#/epic-linked");
        assertThat(properties.getDeltaSafetyMargin()).isEqualTo(Duration.ofHours(24));
        assertThat(properties.isDiagnosticsVerbose()).isTrue();
        assertThat(properties.isConfidentialClient()).isTrue();
    }

    @Test
    void blankOrMissingSecretIsNotConfidential() {
        final EpicProperties properties = new EpicProperties();

        assertThat(properties.isConfidentialClient()).isFalse();
        ReflectionTestUtils.setField(properties, "clientSecret", "  ");
        assertThat(properties.isConfidentialClient()).isFalse();
    }

    @Test
    void sourceConstantIsTheCatalogCode() {
        assertThat(EpicProperties.SOURCE_EPIC).isEqualTo("EPIC");
    }
}
