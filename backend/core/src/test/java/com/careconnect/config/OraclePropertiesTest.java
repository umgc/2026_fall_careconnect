package com.careconnect.config;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** Unit tests for {@link OracleProperties#tenantBaseUrl()} (both trailing-slash branches). */
class OraclePropertiesTest {

    @Test
    void tenantBaseUrlJoinsTenantWhenBaseHasNoTrailingSlash() {
        final OracleProperties p = new OracleProperties();
        p.setBaseUrl("https://fhir-open.cerner.com/r4");
        p.setTenant("tenant-1");
        assertThat(p.tenantBaseUrl()).isEqualTo("https://fhir-open.cerner.com/r4/tenant-1");
    }

    @Test
    void tenantBaseUrlStripsTrailingSlashFromBase() {
        final OracleProperties p = new OracleProperties();
        p.setBaseUrl("https://fhir-open.cerner.com/r4/");
        p.setTenant("tenant-1");
        assertThat(p.tenantBaseUrl()).isEqualTo("https://fhir-open.cerner.com/r4/tenant-1");
    }

    @Test
    void defaultsAreTheOpenSandbox() {
        final OracleProperties p = new OracleProperties();
        assertThat(p.isEnabled()).isFalse();
        assertThat(p.tenantBaseUrl()).startsWith("https://fhir-open.cerner.com/r4/");
        assertThat(p.getSandboxPatientId()).isNotBlank();
    }
}
