package com.careconnect.dto.ehr;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Epic SMART-on-FHIR token endpoint response.
 *
 * <p>Epic returns the patient FHIR id in the {@code patient} launch-context field alongside the
 * OAuth tokens. Unknown fields (id_token, scope, token_type, etc.) are ignored.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record EpicTokenResponse(
        @JsonProperty("access_token") String accessToken,
        @JsonProperty("refresh_token") String refreshToken,
        @JsonProperty("token_type") String tokenType,
        @JsonProperty("expires_in") Long expiresIn,
        @JsonProperty("scope") String scope,
        @JsonProperty("patient") String patient) {
}
