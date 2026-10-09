package com.careconnect.service.ehr.athena;

import java.util.Set;

/**
 * Supplies a usable athenahealth bearer token, hiding which OAuth leg produced it.
 *
 * <p>The 2-legged ({@code client_credentials}) implementation is
 * {@link AthenaClientCredentialsTokenService}. A 3-legged implementation can be added later
 * without touching the FHIR client or the sync pipeline, which only need a token.
 */
public interface AthenaTokenProvider {

    /**
     * A valid bearer token, acquiring or renewing as needed.
     *
     * @throws IllegalStateException when no token can be obtained, whatever the reason
     */
    String accessToken();

    /**
     * Scopes athena actually granted. May be narrower than those requested, so callers must
     * check this before attempting a resource type rather than assuming the configured list.
     *
     * @throws IllegalStateException when no token can be obtained, whatever the reason
     */
    Set<String> grantedScopes();
}
