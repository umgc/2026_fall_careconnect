package com.careconnect.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Epic SMART-on-FHIR configuration (Phase 0, Task 5.3 / doc 1_8).
 *
 * <p>Holds the sandbox/production FHIR base URL, OAuth client id, redirect URI, and the
 * minimum-necessary read scopes. Values mirror the {@code google.oauth.*} block in
 * {@code application-dev.properties}. This bean is always present (it only carries config);
 * the Epic beans that use it are gated on {@code careconnect.epic.enabled} via
 * {@link EpicAccessConfig} and the Epic controller/services.
 */
@Component
public class EpicProperties {

    @Value("${careconnect.epic.enabled:false}")
    private boolean enabled;

    @Value("${epic.oauth.fhir-base-url:https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4}")
    private String fhirBaseUrl;

    @Value("${epic.oauth.client-id:}")
    private String clientId;

    /** Optional; only set when the Epic app is registered as a confidential client. */
    @Value("${epic.oauth.client-secret:}")
    private String clientSecret;

    @Value("${epic.oauth.redirect-uri:http://localhost:8081/api/epic/callback}")
    private String redirectUri;

    @Value("${epic.oauth.scopes:openid fhirUser offline_access patient/Patient.read}")
    private String scopes;

    /** Deep link the callback redirects back to so the mobile (Android/iOS) app resumes. */
    @Value("${epic.oauth.app-return-deeplink:careconnect://epic/linked}")
    private String appReturnDeepLink;

    /**
     * Web return URL the callback redirects to when the connect flow was started from the web app
     * (returnMode=web). Uses the Flutter hash-router path so the SPA can route to it. The callback
     * appends {@code ?status=ok|error}.
     */
    @Value("${epic.oauth.web-return-url:http://localhost:3000/#/epic-linked}")
    private String webReturnUrl;

    /** Discriminator stored on credentials, chunks (source_kind) and audit rows. */
    public static final String SOURCE_EPIC = "EPIC";

    public boolean isEnabled() { return enabled; }
    public String getFhirBaseUrl() { return fhirBaseUrl; }
    public String getClientId() { return clientId; }
    public String getClientSecret() { return clientSecret; }
    public String getRedirectUri() { return redirectUri; }
    public String getScopes() { return scopes; }
    public String getAppReturnDeepLink() { return appReturnDeepLink; }
    public String getWebReturnUrl() { return webReturnUrl; }

    public boolean isConfidentialClient() {
        return clientSecret != null && !clientSecret.isBlank();
    }
}
