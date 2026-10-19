package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.service.ehr.EhrApiClient;
import com.careconnect.service.ehr.EhrAuditService;
import com.careconnect.service.ehr.EhrSourceResolver;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Read-only athenahealth FHIR R4 adapter, the athena implementation of {@link EhrApiClient}.
 *
 * <p>Three athena behaviours shape it, each confirmed against the preview sandbox:
 * <ul>
 *   <li>athena is one database per practice, and every search must name the practice in
 *       {@code ah-practice} (without it athena answers 400). Callers pass it: a linked patient's
 *       practice comes from their chart id via {@link #practiceFor}.</li>
 *   <li>An over-broad query is answered with HTTP 200 and a fatal {@code OperationOutcome}
 *       inside {@code Bundle.entry}, marked {@code search.mode=outcome}. Outcome entries are never
 *       returned as data, and a fatal one fails the call.</li>
 *   <li>Paging is an opaque {@code cursor} carried in {@code link[next]}, followed verbatim.</li>
 * </ul>
 *
 * <p>Every call is audited against the CareConnect user who caused it. Under 2-legged OAuth athena
 * only knows that this application read a chart, so {@code ehr_audit_event} is the one record that
 * ties a person to the access.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.athena.enabled", havingValue = "true")
public class AthenaFhirClient implements EhrApiClient {

    /** Hard stop on cursor paging, so a source that keeps returning next links cannot loop forever. */
    static final int MAX_PAGES = 50;

    private static final MediaType FHIR_JSON = MediaType.valueOf("application/fhir+json");
    private static final String SOURCE = AthenaProperties.SOURCE_ATHENA;

    /** An athena id's leading practice number: {@code a-195900.E-10037} gives 195900. */
    private static final Pattern ID_PRACTICE = Pattern.compile("a-(\\d+)\\.");

    private final RestTemplate http;
    private final AthenaProperties cfg;
    private final AthenaTokenProvider tokens;
    private final EhrAuditService audit;
    private final PatientRepository patients;
    private final EhrPatientCrosswalkRepository crosswalks;
    private final EhrSourceResolver sources;

    /** Result of a paged search. A result that stopped at {@link #MAX_PAGES} is not the full set. */
    public record SearchResult(List<JsonNode> resources, boolean complete) {
    }

    @Override
    public String sourceCode() {
        return SOURCE;
    }

    /** Fetch one resource type for the user's linked athena chart, in that chart's practice. */
    @Override
    public List<JsonNode> fetch(final Long userId, final String resourceType, final Map<String, String> params) {
        final String athenaPatientId = linkedPatientId(userId).orElseThrow(() ->
                new IllegalStateException("user " + userId + " is not linked to an athenahealth chart"));
        final String practice = practiceFor(athenaPatientId).orElseThrow(() ->
                new IllegalStateException("user " + userId + "'s athena chart is in a practice "
                        + "this deployment is not configured to read"));
        final Map<String, String> query = new LinkedHashMap<>(params == null ? Map.of() : params);
        query.put("patient", athenaPatientId);
        return search(userId, practice, resourceType, query).resources();
    }

    @Override
    public List<JsonNode> everything(final Long userId) {
        throw new UnsupportedOperationException(
                "athenahealth does not offer Patient/$everything; fetch each resource type instead");
    }

    /** The athena chart id linked to this user in ehr_patient_crosswalk. Never searches athena. */
    public Optional<String> linkedPatientId(final Long userId) {
        final Long sourceId = sources.idForCode(SOURCE);
        if (sourceId == null) {
            return Optional.empty();
        }
        return patients.findByUserId(userId)
                .flatMap(patient -> crosswalks.findByPatientIdAndSourceId(patient.getId(), sourceId))
                .map(EhrPatientCrosswalk::getExternalPatientId)
                .filter(id -> !id.isBlank());
    }

    /**
     * The practice an athena id belongs to, in {@code ah-practice} form. athena ids carry their
     * practice number ({@code a-195900.E-10037} is patient 10037 in practice 195900), so this needs no
     * lookup. Empty when the id is not in that shape, or its practice is not one this deployment is
     * configured to read.
     */
    public Optional<String> practiceFor(final String athenaId) {
        final Matcher matcher = ID_PRACTICE.matcher(athenaId == null ? "" : athenaId);
        return matcher.lookingAt() ? cfg.practiceWithNumber(matcher.group(1)) : Optional.empty();
    }

    /**
     * Search one resource type in one practice, following cursor paging.
     *
     * @param actorUserId the CareConnect user the access is audited against
     * @param practiceId  the practice to search, in {@code ah-practice} form
     */
    public SearchResult search(final Long actorUserId, final String practiceId, final String resourceType,
                               final Map<String, String> params) {
        final UriComponentsBuilder first = UriComponentsBuilder.fromUriString(cfg.getFhirBaseUrl())
                .pathSegment(resourceType)
                .queryParam("ah-practice", practiceId);
        params.forEach(first::queryParam);
        // build() then encode(), never encode() then build(): the values include user-entered names,
        // and the other order would read a literal "{...}" in a name as a URI template variable.
        URI next = first.build().encode().toUri();

        final List<JsonNode> out = new ArrayList<>();
        int pages = 0;
        try {
            while (next != null && pages < MAX_PAGES) {
                final JsonNode bundle = get(next, resourceType);
                collect(bundle, resourceType, out);
                next = nextLink(bundle);
                pages++;
            }
        } catch (RuntimeException ex) {
            audit.record(actorUserId, SOURCE, "ATHENA_SEARCH", resourceType, null, EhrAuditService.OUTCOME_ERROR);
            throw ex;
        }
        final boolean complete = next == null;
        if (!complete) {
            log.warn("athena {} search stopped after {} pages; the result is incomplete", resourceType, MAX_PAGES);
        }
        audit.record(actorUserId, SOURCE, "ATHENA_SEARCH", resourceType, null,
                out.isEmpty() ? EhrAuditService.OUTCOME_EMPTY : EhrAuditService.OUTCOME_OK);
        return new SearchResult(List.copyOf(out), complete);
    }

    /**
     * Read one resource by id.
     *
     * @param actorUserId the CareConnect user the access is audited against
     * @param practiceId  the practice the resource belongs to, in {@code ah-practice} form
     */
    public JsonNode read(final Long actorUserId, final String practiceId, final String resourceType,
                         final String id) {
        final URI uri = UriComponentsBuilder.fromUriString(cfg.getFhirBaseUrl())
                .pathSegment(resourceType, id)
                .queryParam("ah-practice", practiceId)
                .build()
                .encode()
                .toUri();
        try {
            final JsonNode resource = get(uri, resourceType);
            if (resource == null || !resourceType.equals(resource.path("resourceType").asText())) {
                throw new AthenaFhirException(AthenaFhirException.Kind.REJECTED,
                        "athena returned no " + resourceType + " for a read by id");
            }
            audit.record(actorUserId, SOURCE, "ATHENA_READ", resourceType, null, EhrAuditService.OUTCOME_OK);
            return resource;
        } catch (RuntimeException ex) {
            audit.record(actorUserId, SOURCE, "ATHENA_READ", resourceType, null, EhrAuditService.OUTCOME_ERROR);
            throw ex;
        }
    }

    private JsonNode get(final URI uri, final String resourceType) {
        final String token;
        try {
            token = tokens.accessToken();
        } catch (IllegalStateException ex) {
            // The token service has already logged why (quota, scopes, credentials).
            throw new AthenaFhirException(AthenaFhirException.Kind.UNAVAILABLE,
                    "no athenahealth token is available", ex);
        }
        final HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        headers.setAccept(List.of(FHIR_JSON, MediaType.APPLICATION_JSON));
        try {
            return http.exchange(uri, HttpMethod.GET, new HttpEntity<>(headers), JsonNode.class).getBody();
        } catch (RestClientResponseException ex) {
            // Status only. The body can echo the search values, which for Patient means name and DOB.
            final int status = ex.getStatusCode().value();
            log.warn("athena {} request returned HTTP {}", resourceType, status);
            throw new AthenaFhirException(kindFor(status),
                    "athena " + resourceType + " request failed with HTTP " + status, ex);
        } catch (ResourceAccessException ex) {
            throw new AthenaFhirException(AthenaFhirException.Kind.UNAVAILABLE,
                    "athena " + resourceType + " request could not reach athenahealth", ex);
        } catch (RestClientException ex) {
            throw new AthenaFhirException(AthenaFhirException.Kind.UNAVAILABLE,
                    "athena " + resourceType + " response could not be read", ex);
        }
    }

    static AthenaFhirException.Kind kindFor(final int status) {
        if (status == 403) {
            return AthenaFhirException.Kind.SCOPE_DENIED;
        }
        if (status == 401 || status == 429 || status >= 500) {
            return AthenaFhirException.Kind.UNAVAILABLE;
        }
        return AthenaFhirException.Kind.REJECTED;
    }

    /** Adds {@code Bundle.entry[].resource} of the expected type to {@code out}. */
    static void collect(final JsonNode bundle, final String resourceType, final List<JsonNode> out) {
        if (bundle == null) {
            return;
        }
        for (final JsonNode entry : bundle.path("entry")) {
            final JsonNode resource = entry.path("resource");
            if ("outcome".equals(entry.path("search").path("mode").asText())
                    || "OperationOutcome".equals(resource.path("resourceType").asText())) {
                final String fatalCode = fatalIssueCode(resource);
                if (fatalCode != null) {
                    throw new AthenaFhirException(AthenaFhirException.Kind.REJECTED,
                            "athena rejected the " + resourceType + " search (" + fatalCode + ")");
                }
                continue;
            }
            // Drops anything pulled in alongside the match, e.g. via _include.
            if (resourceType.equals(resource.path("resourceType").asText())) {
                out.add(resource);
            }
        }
    }

    private static String fatalIssueCode(final JsonNode outcome) {
        for (final JsonNode issue : outcome.path("issue")) {
            if ("fatal".equals(issue.path("severity").asText())) {
                return issue.path("code").asText("unknown");
            }
        }
        return null;
    }

    /**
     * The next page, or null when there is none. A next link is followed only when it points back at
     * the configured athena host, because the request carries our bearer token. Any other next link
     * fails the call rather than ending paging early: an early stop would look like a complete
     * result, and a sync prunes rows that a complete result no longer contains.
     */
    URI nextLink(final JsonNode bundle) {
        if (bundle == null) {
            return null;
        }
        for (final JsonNode link : bundle.path("link")) {
            if ("next".equals(link.path("relation").asText()) && link.path("url").isTextual()) {
                return checkedNextLink(link.path("url").asText());
            }
        }
        return null;
    }

    private URI checkedNextLink(final String url) {
        final URI next;
        try {
            next = URI.create(url);
        } catch (IllegalArgumentException ex) {
            throw new AthenaFhirException(AthenaFhirException.Kind.REJECTED,
                    "athena returned an unparseable next link", ex);
        }
        final URI base = URI.create(cfg.getFhirBaseUrl());
        if (!Objects.equals(base.getScheme(), next.getScheme())
                || !Objects.equals(base.getHost(), next.getHost())
                || base.getPort() != next.getPort()) {
            throw new AthenaFhirException(AthenaFhirException.Kind.REJECTED,
                    "athena returned a next link to a different host");
        }
        return next;
    }
}
