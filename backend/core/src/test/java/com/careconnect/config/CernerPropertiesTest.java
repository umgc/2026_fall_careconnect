package com.careconnect.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class CernerPropertiesTest {

    @Test
    void exposesConfiguredValuesAndDetectsConfidentialClient() {
        final CernerProperties properties = new CernerProperties();
        ReflectionTestUtils.setField(properties, "enabled", true);
        ReflectionTestUtils.setField(properties, "fhirBaseUrl", "https://example.test/fhir/");
        ReflectionTestUtils.setField(properties, "clientId", "client-id");
        ReflectionTestUtils.setField(properties, "clientSecret", "secret");
        ReflectionTestUtils.setField(properties, "redirectUri", "https://app.test/callback");
        ReflectionTestUtils.setField(properties, "scopes", "openid patient/Patient.read");
        ReflectionTestUtils.setField(properties, "authorizationEndpoint", "https://auth.test/authorize");
        ReflectionTestUtils.setField(properties, "tokenEndpoint", "https://auth.test/token");
        ReflectionTestUtils.setField(properties, "httpTimeout", Duration.ofSeconds(10));
        ReflectionTestUtils.setField(properties, "appReturnDeepLink", "careconnect://linked");
        ReflectionTestUtils.setField(properties, "webReturnUrl", "https://app.test/settings");

        assertThat(properties.isEnabled()).isTrue();
        assertThat(properties.getFhirBaseUrl()).isEqualTo("https://example.test/fhir/");
        assertThat(properties.getClientId()).isEqualTo("client-id");
        assertThat(properties.getRedirectUri()).isEqualTo("https://app.test/callback");
        assertThat(properties.getScopes()).contains("patient/Patient.read");
        assertThat(properties.getAuthorizationEndpoint()).endsWith("/authorize");
        assertThat(properties.getTokenEndpoint()).endsWith("/token");
        assertThat(properties.getHttpTimeout()).isEqualTo(Duration.ofSeconds(10));
        assertThat(properties.getAppReturnDeepLink()).isEqualTo("careconnect://linked");
        assertThat(properties.getWebReturnUrl()).isEqualTo("https://app.test/settings");
        assertThat(properties.isConfidentialClient()).isTrue();
    }

    @Test
    void blankOrMissingSecretIsNotConfidential() {
        final CernerProperties properties = new CernerProperties();

        assertThat(properties.isConfidentialClient()).isFalse();
        ReflectionTestUtils.setField(properties, "clientSecret", "  ");
        assertThat(properties.isConfidentialClient()).isFalse();
    }
}
