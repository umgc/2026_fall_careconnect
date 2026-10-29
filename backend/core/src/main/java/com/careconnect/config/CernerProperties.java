package com.careconnect.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Duration;

/** Server-controlled Oracle Health SMART-on-FHIR configuration for Team C's read-only adapter. */
@Component
public class CernerProperties {

    /** Stable code seeded in {@code ehr_source}; use it throughout persistence and API mapping. */
    public static final String SOURCE_ORACLE_HEALTH = "ORACLE_HEALTH";

    @Value("${careconnect.cerner.enabled:false}")
    private boolean enabled;

    @Value("${cerner.oauth.fhir-base-url:}")
    private String fhirBaseUrl;

    @Value("${cerner.oauth.client-id:}")
    private String clientId;

    @Value("${cerner.oauth.client-secret:}")
    private String clientSecret;

    @Value("${cerner.oauth.redirect-uri:http://localhost:8081/api/oracle-health/callback}")
    private String redirectUri;

    @Value("${cerner.oauth.scopes:openid fhirUser offline_access launch/patient patient/Patient.read patient/Condition.read patient/AllergyIntolerance.read patient/Encounter.read patient/Appointment.read}")
    private String scopes;

    @Value("${cerner.oauth.authorization-endpoint:}")
    private String authorizationEndpoint;

    @Value("${cerner.oauth.token-endpoint:}")
    private String tokenEndpoint;

    @Value("${cerner.http.timeout:10s}")
    private Duration httpTimeout;

    @Value("${cerner.oauth.app-return-deeplink:careconnect://oracle-health/linked}")
    private String appReturnDeepLink;

    @Value("${cerner.oauth.web-return-url:http://localhost:3000/#/settings}")
    private String webReturnUrl;

    public boolean isEnabled() { return enabled; }
    public String getFhirBaseUrl() { return fhirBaseUrl; }
    public String getClientId() { return clientId; }
    public String getClientSecret() { return clientSecret; }
    public String getRedirectUri() { return redirectUri; }
    public String getScopes() { return scopes; }
    public String getAuthorizationEndpoint() { return authorizationEndpoint; }
    public String getTokenEndpoint() { return tokenEndpoint; }
    public Duration getHttpTimeout() { return httpTimeout; }
    public String getAppReturnDeepLink() { return appReturnDeepLink; }
    public String getWebReturnUrl() { return webReturnUrl; }

    public boolean isConfidentialClient() {
        return clientSecret != null && !clientSecret.isBlank();
    }
}
