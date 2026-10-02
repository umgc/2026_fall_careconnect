package com.careconnect.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * athenahealth connection configuration.
 *
 * <p>Unlike Epic, the OAuth endpoints are NOT derivable from the FHIR base URL: athena serves
 * OAuth from {@code /oauth2/v1/*} while FHIR R4 lives at {@code /fhir/r4}. They are therefore
 * configured explicitly rather than derived. The values below were confirmed against athena's
 * published {@code .well-known/smart-configuration} on the preview host.
 *
 * <p>Setters exist for unit tests; Spring populates the fields via {@code @Value}.
 */
@Component
@Getter
@Setter
public class AthenaProperties {

    /** Discriminator stored on mirrored resources and audit rows. */
    public static final String SOURCE_ATHENA = "ATHENA";

    @Value("${careconnect.athena.enabled:false}")
    private boolean enabled;

    @Value("${athena.oauth.token-url:https://api.preview.platform.athenahealth.com/oauth2/v1/token}")
    private String tokenUrl;

    /** Unused by the 2-legged flow; present so the 3-legged leg has somewhere to read it from. */
    @Value("${athena.oauth.authorize-url:https://api.preview.platform.athenahealth.com/oauth2/v1/authorize}")
    private String authorizeUrl;

    @Value("${athena.oauth.introspect-url:https://api.preview.platform.athenahealth.com/oauth2/v1/introspect}")
    private String introspectUrl;

    @Value("${athena.oauth.revoke-url:https://api.preview.platform.athenahealth.com/oauth2/v1/revoke}")
    private String revokeUrl;

    @Value("${athena.oauth.client-id:}")
    private String clientId;

    @Value("${athena.oauth.client-secret:}")
    private String clientSecret;

    /**
     * Space-delimited, case-sensitive scopes. athena rejects wildcards, so every resource is
     * listed explicitly, and requesting a scope the portal app is not configured for fails the
     * WHOLE request with 400 {@code Invalid Scope} rather than degrading. Keep this list in sync
     * with the app registration.
     */
    @Value("${athena.oauth.scopes:system/Patient.read}")
    private String scopes;

    @Value("${athena.fhir.base-url:https://api.preview.platform.athenahealth.com/fhir/r4}")
    private String fhirBaseUrl;

    /**
     * Practice context, required as the {@code ah-practice} SEARCH PARAMETER on every FHIR call
     * (not a path segment, not a header). Format is athena's prefixed id, e.g.
     * {@code a-1.Practice-195900}; the bare numeric id is rejected.
     */
    @Value("${athena.fhir.practice-id:}")
    private String practiceId;

    public boolean hasCredentials() {
        return clientId != null && !clientId.isBlank()
                && clientSecret != null && !clientSecret.isBlank();
    }

    /** Requested scopes as a set, for comparison against what athena actually granted. */
    public Set<String> requestedScopes() {
        if (scopes == null || scopes.isBlank()) {
            return Set.of();
        }
        return new LinkedHashSet<>(Arrays.asList(scopes.trim().split("\\s+")));
    }
}
