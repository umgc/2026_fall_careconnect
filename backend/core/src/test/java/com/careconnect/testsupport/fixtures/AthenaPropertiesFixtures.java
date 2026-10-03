package com.careconnect.testsupport.fixtures;

import com.careconnect.config.AthenaProperties;

/**
 * Shared {@link AthenaProperties} builders for backend unit tests.
 *
 * <p>
 * {@code AthenaProperties} is immutable, so tests cannot adjust a constructed instance the way
 * they could when it exposed setters. This builder gives them readable, named overrides on top of
 * a valid baseline instead of a ten-argument positional constructor call.
 * </p>
 */
public final class AthenaPropertiesFixtures {

    public static final String TOKEN_URL = "https://athena.example/oauth2/v1/token";
    public static final String FHIR_BASE_URL = "https://athena.example/fhir/r4";
    public static final String CLIENT_ID = "test-id";
    public static final String CLIENT_SECRET = "test-secret";
    public static final String PRACTICE_ID = "a-1.Practice-1";

    private AthenaPropertiesFixtures() {
        // Utility class
    }

    /**
     * Starts from an enabled configuration with credentials, one scope and a practice, pointing
     * at a fake host so a missed mock can never reach the real athena sandbox.
     */
    public static Builder builder() {
        return new Builder();
    }

    /** Named overrides for the fields tests actually vary. */
    public static final class Builder {

        private boolean enabled = true;
        private String tokenUrl = TOKEN_URL;
        private String clientId = CLIENT_ID;
        private String clientSecret = CLIENT_SECRET;
        private String scopes = "system/Patient.read";
        private String fhirBaseUrl = FHIR_BASE_URL;
        private String practiceId = PRACTICE_ID;

        private Builder() {
        }

        public Builder enabled(final boolean value) {
            this.enabled = value;
            return this;
        }

        public Builder tokenUrl(final String value) {
            this.tokenUrl = value;
            return this;
        }

        public Builder clientId(final String value) {
            this.clientId = value;
            return this;
        }

        public Builder clientSecret(final String value) {
            this.clientSecret = value;
            return this;
        }

        public Builder scopes(final String value) {
            this.scopes = value;
            return this;
        }

        public Builder fhirBaseUrl(final String value) {
            this.fhirBaseUrl = value;
            return this;
        }

        public Builder practiceId(final String value) {
            this.practiceId = value;
            return this;
        }

        public AthenaProperties build() {
            return new AthenaProperties(
                    enabled,
                    tokenUrl,
                    "https://athena.example/oauth2/v1/authorize",
                    "https://athena.example/oauth2/v1/introspect",
                    "https://athena.example/oauth2/v1/revoke",
                    clientId,
                    clientSecret,
                    scopes,
                    fhirBaseUrl,
                    practiceId);
        }
    }
}
