package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.net.URI;

/** Constructs Oracle Health HTTP boundaries only when the Cerner integration is enabled. */
@Configuration
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class CernerIntegrationConfiguration {

    @Bean
    CernerAllergyHttpClient cernerAllergyHttpClient(final CernerProperties properties) {
        String base = properties.getFhirBaseUrl();
        if (base == null || base.isBlank()) {
            throw new IllegalStateException("cerner.oauth.fhir-base-url is required");
        }
        if (!base.endsWith("/")) {
            base += "/";
        }
        return new CernerAllergyHttpClient(URI.create(base), properties.getHttpTimeout());
    }

    @Bean
    CernerFhirBundleHttpClient cernerFhirBundleHttpClient(final CernerProperties properties) {
        String base = properties.getFhirBaseUrl();
        if (base == null || base.isBlank()) {
            throw new IllegalStateException("cerner.oauth.fhir-base-url is required");
        }
        if (!base.endsWith("/")) {
            base += "/";
        }
        return new CernerFhirBundleHttpClient(URI.create(base), properties.getHttpTimeout());
    }
}
