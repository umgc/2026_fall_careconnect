package com.careconnect.dto.ehr;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * athenahealth token endpoint response.
 *
 * <p>A {@code client_credentials} grant never carries a refresh token (RFC 6749 section 4.4.3)
 * and never carries SMART launch context, so there is no {@code patient} field to read: the
 * patient must be resolved by FHIR search instead. {@code scope} reflects what athena actually
 * granted, which can be narrower than what was requested.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record AthenaTokenResponse(
        @JsonProperty("access_token") String accessToken,
        @JsonProperty("token_type") String tokenType,
        @JsonProperty("expires_in") Long expiresIn,
        @JsonProperty("scope") String scope) {
}
