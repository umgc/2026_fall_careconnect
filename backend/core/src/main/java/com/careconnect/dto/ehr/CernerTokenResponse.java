package com.careconnect.dto.ehr;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

/** OAuth token response plus SMART patient launch context returned by Oracle Health. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record CernerTokenResponse(
        @JsonProperty("access_token") String accessToken,
        @JsonProperty("refresh_token") String refreshToken,
        @JsonProperty("token_type") String tokenType,
        @JsonProperty("expires_in") Long expiresIn,
        @JsonProperty("scope") String scope,
        @JsonProperty("patient") String patient) {
}
