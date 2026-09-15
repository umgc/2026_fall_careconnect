package com.careconnect.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuration properties for the athenahealth FHIR R4 adapter.
 * <p>
 * Prefix: {@code careconnect.ehr.athenahealth}
 * <p>
 * Example application.properties entries (values come from environment variables — never commit
 * a real client id/secret to this file, see {@code auth.client-id} / {@code auth.client-secret}):
 * <pre>
 *   careconnect.ehr.athenahealth.api.base-url=https://api.platform.athenahealth.com/fhir/r4
 *   careconnect.ehr.athenahealth.auth.token-url=https://api.platform.athenahealth.com/oauth2/v1/token
 *   careconnect.ehr.athenahealth.auth.client-id=${ATHENAHEALTH_CLIENT_ID:}
 *   careconnect.ehr.athenahealth.auth.client-secret=${ATHENAHEALTH_CLIENT_SECRET:}
 * </pre>
 */
@ConfigurationProperties(prefix = "careconnect.ehr.athenahealth")
@Getter
@Setter
public class AthenahealthProperties {

    private Api api = new Api();
    private Auth auth = new Auth();

    @Getter
    @Setter
    public static class Api {
        /** Base URL for athenahealth's FHIR R4 API. */
        private String baseUrl = "https://api.platform.athenahealth.com/fhir/r4";
    }

    @Getter
    @Setter
    public static class Auth {
        /** OAuth2 client-credentials token endpoint. */
        private String tokenUrl = "https://api.platform.athenahealth.com/oauth2/v1/token";
        /** Client id issued by athenahealth for this application. */
        private String clientId = "";
        /** Client secret issued by athenahealth for this application. */
        private String clientSecret = "";
        /**
         * OAuth2 scope requested at the token endpoint. Must match what this app was actually
         * granted in the athenahealth Developer Portal (Credentials/Scopes tab) — a mismatch
         * fails token acquisition with {@code access_denied} / "Policy evaluation failed", not a
         * client-id/secret error. Space-separated if the app was granted more than one scope.
         */
        private String scope = "system/*.read";
    }
}
