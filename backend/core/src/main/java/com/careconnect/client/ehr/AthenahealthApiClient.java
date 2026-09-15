package com.careconnect.client.ehr;

import com.careconnect.config.AthenahealthProperties;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

/**
 * athenahealth FHIR R4 adapter. Fetches raw resources only — mapping into canonical entities
 * (for example {@link com.careconnect.model.ehr.EhrAppointmentRecord}) is shared logic, not
 * duplicated here.
 *
 * <p>Uses the existing {@link RestTemplate} bean rather than adding a HAPI FHIR dependency: there
 * is no FHIR client library in this module today, no athenahealth sandbox credentials configured
 * yet, and pulling in a FHIR library is a shared-cost decision for its own PR. Responses are
 * parsed with plain Jackson {@link JsonNode}, which is all the current mapping needs.
 *
 * <p>Token acquisition (OAuth2 client-credentials) is a simple in-memory cache, not a
 * production-grade token manager — sufficient for one low-volume adapter, revisit if a second
 * source needs the same pattern.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class AthenahealthApiClient implements EhrApiClient {

    private static final String SOURCE_CODE = "ATHENAHEALTH";

    /** The one resource type that is fetched by direct id, not by patient-reference search. */
    private static final String RESOURCE_TYPE_PATIENT = "Patient";

    /** Seconds of safety margin subtracted from the token's reported lifetime. */
    private static final long TOKEN_EXPIRY_SAFETY_MARGIN_SECONDS = 30;

    /** Fallback token lifetime when the token response omits {@code expires_in}. */
    private static final long DEFAULT_TOKEN_TTL_SECONDS = 300;

    private final RestTemplate restTemplate;
    private final AthenahealthProperties properties;

    private volatile String cachedToken;
    private volatile Instant tokenExpiresAt = Instant.EPOCH;

    @Override
    public String sourceCode() {
        return SOURCE_CODE;
    }

    @Override
    public List<JsonNode> fetchResources(final String resourceType, final String externalPatientId) {
        return RESOURCE_TYPE_PATIENT.equals(resourceType)
                ? fetchById(resourceType, externalPatientId)
                : searchByPatientReference(resourceType, externalPatientId);
    }

    /**
     * {@code Patient} is the patient, not something referencing one, so FHIR has no
     * {@code ?patient=} search for it — {@code externalPatientId} is directly the resource's own
     * id, fetched with a plain {@code GET /Patient/{id}}. That call returns the resource itself,
     * not a search {@code Bundle}, so the result is wrapped in a single-element list rather than
     * run through {@link #extractBundleEntries}.
     */
    private List<JsonNode> fetchById(final String resourceType, final String externalId) {
        final String url = properties.getApi().getBaseUrl() + "/" + resourceType + "/" + externalId;

        log.info("[athenahealth] Fetching {}/{}", resourceType, externalId);
        final ResponseEntity<JsonNode> response = restTemplate.exchange(
                url, HttpMethod.GET, new HttpEntity<>(authHeaders()), JsonNode.class);

        final JsonNode resource = response.getBody();
        return resource == null ? new ArrayList<>() : new ArrayList<>(List.of(resource));
    }

    /**
     * Every other resource type (Appointment, Coverage, ExplanationOfBenefit, ...) is a
     * patient-compartment resource: it references the patient rather than being one, so it is
     * fetched by FHIR's standard {@code ?patient=<id>} search, which returns a {@code Bundle}.
     */
    private List<JsonNode> searchByPatientReference(
            final String resourceType, final String externalPatientId) {
        final String url = UriComponentsBuilder
                .fromUriString(properties.getApi().getBaseUrl() + "/" + resourceType)
                .queryParam("patient", externalPatientId)
                .toUriString();

        log.info("[athenahealth] Fetching {} for external patient {}", resourceType, externalPatientId);
        final ResponseEntity<JsonNode> response = restTemplate.exchange(
                url, HttpMethod.GET, new HttpEntity<>(authHeaders()), JsonNode.class);

        return extractBundleEntries(response.getBody());
    }

    private HttpHeaders authHeaders() {
        final HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(accessToken());
        headers.setAccept(List.of(MediaType.APPLICATION_JSON));
        return headers;
    }

    private List<JsonNode> extractBundleEntries(final JsonNode bundle) {
        final List<JsonNode> resources = new ArrayList<>();
        if (bundle == null || !bundle.hasNonNull("entry")) {
            return resources;
        }
        for (final JsonNode entry : bundle.get("entry")) {
            final JsonNode resource = entry.get("resource");
            if (resource != null) {
                resources.add(resource);
            }
        }
        return resources;
    }

    private synchronized String accessToken() {
        if (cachedToken != null && Instant.now().isBefore(tokenExpiresAt)) {
            return cachedToken;
        }

        final HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

        final MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
        body.add("grant_type", "client_credentials");
        body.add("client_id", properties.getAuth().getClientId());
        body.add("client_secret", properties.getAuth().getClientSecret());
        body.add("scope", properties.getAuth().getScope());

        final ResponseEntity<JsonNode> response = restTemplate.postForEntity(
                properties.getAuth().getTokenUrl(), new HttpEntity<>(body, headers), JsonNode.class);

        final JsonNode tokenResponse = response.getBody();
        if (tokenResponse == null || !tokenResponse.hasNonNull("access_token")) {
            throw new IllegalStateException("athenahealth token endpoint returned no access_token");
        }

        cachedToken = tokenResponse.get("access_token").asText();
        final long expiresInSeconds =
                tokenResponse.path("expires_in").asLong(DEFAULT_TOKEN_TTL_SECONDS);
        tokenExpiresAt = Instant.now()
                .plusSeconds(Math.max(0, expiresInSeconds - TOKEN_EXPIRY_SAFETY_MARGIN_SECONDS));
        return cachedToken;
    }
}
