package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
import com.careconnect.model.ehr.EhrAuditEvent;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Epic read-only FHIR adapter (Findings R1 first adapter). {@code RestTemplate} + Bearer +
 * {@code application/fhir+json}, returning {@link JsonNode} resources with Bundle paging.
 * Every fetch is audited (fail-soft, hashed) via {@link EhrAuditService}.
 *
 * <p>Gated on {@code careconnect.epic.enabled}; templates: the Google-Health REST fetch and the
 * {@code service/evv/*EvvClient} external clients.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.epic.enabled", havingValue = "true")
public class EpicFhirClient implements EhrApiClient {

    private static final int MAX_PAGES = 20;
    private static final MediaType FHIR_JSON = MediaType.valueOf("application/fhir+json");

    private final RestTemplate http;
    private final EpicProperties cfg;
    private final EpicOAuthService oauth;
    private final EhrAuditService audit;

    @Override
    public String sourceCode() {
        return EpicProperties.SOURCE_EPIC;
    }

    @Override
    public List<JsonNode> fetch(Long userId, String resourceType, Map<String, String> params) {
        String token = oauth.validAccessToken(userId);
        String patientId = oauth.patientFhirId(userId);
        HttpEntity<Void> entity = new HttpEntity<>(bearerHeaders(token));

        UriComponentsBuilder b = UriComponentsBuilder
                .fromHttpUrl(cfg.getFhirBaseUrl() + "/" + resourceType)
                .queryParam("patient", patientId);
        if (params != null) {
            params.forEach(b::queryParam);
        }
        String url = b.build(true).toUriString();

        List<JsonNode> out = new ArrayList<>();
        try {
            int pages = 0;
            while (url != null && pages < MAX_PAGES) {
                ResponseEntity<JsonNode> resp =
                        http.exchange(url, HttpMethod.GET, entity, JsonNode.class);
                JsonNode bundle = resp.getBody();
                extractEntries(bundle, out);
                url = nextLink(bundle);
                pages++;
            }
            // Surface WHAT came back so an "OK but stored nothing" case (a bundle carrying only an
            // informational OperationOutcome, e.g. Epic warning a required search param is missing)
            // is visible rather than silent.
            final String ooText = operationOutcomeText(out);
            log.info("Epic fetch {} params={} -> {} entries, types={}{}",
                    resourceType, params, out.size(), typeSummary(out),
                    ooText.isEmpty() ? "" : ", outcome=[" + ooText + "]");
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_FETCH", resourceType,
                    resourceType, out.isEmpty()
                            ? EhrAuditEvent.OUTCOME_EMPTY : EhrAuditEvent.OUTCOME_OK);
            return out;
        } catch (org.springframework.web.client.RestClientResponseException ex) {
            // Log Epic's actual OperationOutcome body (names the missing/invalid search parameter),
            // which the default RestTemplate error otherwise hides as a bare "400 BAD_REQUEST".
            // A 403 with an empty body carries its reason in WWW-Authenticate (Epic:
            // insufficient_scope = "valid token, but not authorized for this service" → the API is
            // not enabled on the app registration). Log that so the cause isn't a bare "403".
            final String wwwAuth = ex.getResponseHeaders() != null
                    ? ex.getResponseHeaders().getFirst("WWW-Authenticate") : null;
            log.warn("Epic fetch {} params={} -> {} : body='{}' wwwAuthenticate={}", resourceType,
                    params, ex.getStatusCode().value(), ex.getResponseBodyAsString(), wwwAuth);
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_FETCH", resourceType,
                    resourceType, EhrAuditEvent.OUTCOME_ERROR);
            throw ex;
        } catch (RuntimeException ex) {
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_FETCH", resourceType,
                    resourceType, EhrAuditEvent.OUTCOME_ERROR);
            throw ex;
        }
    }

    /** Flatten any OperationOutcome issues in a result to "severity/code: diagnostics" (diagnostics). */
    private static String operationOutcomeText(List<JsonNode> resources) {
        StringBuilder sb = new StringBuilder();
        for (JsonNode r : resources) {
            if (r == null || !"OperationOutcome".equals(r.path("resourceType").asText())) {
                continue;
            }
            JsonNode issues = r.get("issue");
            if (issues == null || !issues.isArray()) {
                continue;
            }
            for (JsonNode is : issues) {
                String diag = is.hasNonNull("diagnostics")
                        ? is.get("diagnostics").asText()
                        : is.path("details").path("text").asText("");
                if (sb.length() > 0) {
                    sb.append(" | ");
                }
                sb.append(is.path("severity").asText("")).append('/')
                        .append(is.path("code").asText("")).append(": ").append(diag);
            }
        }
        return sb.toString();
    }

    /** Compact tally of the resourceTypes present in a fetch result (for diagnostics/logging). */
    private static String typeSummary(List<JsonNode> resources) {
        java.util.Map<String, Integer> counts = new java.util.LinkedHashMap<>();
        for (JsonNode r : resources) {
            String t = r != null && r.hasNonNull("resourceType") ? r.get("resourceType").asText() : "?";
            counts.merge(t, 1, Integer::sum);
        }
        return counts.toString();
    }

    /**
     * Single-resource read: {@code GET {base}/{type}/{id}} with NO {@code patient} search param.
     * Used for demographics ({@code Patient/{patientFhirId}}), which is a read, not a search — the
     * {@link #fetch} path always appends {@code ?patient=} and would 400 on a Patient search.
     * Returns a singleton list (or empty) so callers share the mirror path with {@link #fetch}.
     */
    public List<JsonNode> read(Long userId, String resourceType, String fhirId) {
        String token = oauth.validAccessToken(userId);
        HttpEntity<Void> entity = new HttpEntity<>(bearerHeaders(token));
        String url = cfg.getFhirBaseUrl() + "/" + resourceType + "/" + fhirId;
        List<JsonNode> out = new ArrayList<>();
        try {
            ResponseEntity<JsonNode> resp = http.exchange(url, HttpMethod.GET, entity, JsonNode.class);
            extractEntries(resp.getBody(), out);
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_READ", resourceType,
                    resourceType, out.isEmpty()
                            ? EhrAuditEvent.OUTCOME_EMPTY : EhrAuditEvent.OUTCOME_OK);
            return out;
        } catch (RuntimeException ex) {
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_READ", resourceType,
                    resourceType, EhrAuditEvent.OUTCOME_ERROR);
            throw ex;
        }
    }

    @Override
    public List<JsonNode> everything(Long userId) {
        String token = oauth.validAccessToken(userId);
        String patientId = oauth.patientFhirId(userId);
        HttpEntity<Void> entity = new HttpEntity<>(bearerHeaders(token));
        String url = cfg.getFhirBaseUrl() + "/Patient/" + patientId + "/$everything";
        List<JsonNode> out = new ArrayList<>();
        try {
            // Follow Bundle paging (capped at MAX_PAGES) exactly like fetch() — a first-page-only
            // read silently truncates $everything for patients with a large compartment.
            int pages = 0;
            while (url != null && pages < MAX_PAGES) {
                ResponseEntity<JsonNode> resp =
                        http.exchange(url, HttpMethod.GET, entity, JsonNode.class);
                JsonNode bundle = resp.getBody();
                extractEntries(bundle, out);
                url = nextLink(bundle);
                pages++;
            }
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_EVERYTHING", "Patient",
                    "$everything", out.isEmpty()
                            ? EhrAuditEvent.OUTCOME_EMPTY : EhrAuditEvent.OUTCOME_OK);
            return out;
        } catch (RuntimeException ex) {
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_EVERYTHING", "Patient",
                    "$everything", EhrAuditEvent.OUTCOME_ERROR);
            throw ex;
        }
    }

    private HttpHeaders bearerHeaders(String token) {
        HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(token);
        h.setAccept(List.of(FHIR_JSON, MediaType.APPLICATION_JSON));
        return h;
    }

    /** Collect {@code Bundle.entry[].resource}; for a single-resource read, the node itself. */
    static void extractEntries(JsonNode bundle, List<JsonNode> out) {
        if (bundle == null) {
            return;
        }
        JsonNode entries = bundle.get("entry");
        if (entries != null && entries.isArray()) {
            for (JsonNode entry : entries) {
                JsonNode resource = entry.get("resource");
                if (resource != null && !resource.isNull()) {
                    out.add(resource);
                }
            }
            return;
        }
        // A direct resource read (not a Bundle).
        if (bundle.hasNonNull("resourceType") && !"Bundle".equals(bundle.get("resourceType").asText())) {
            out.add(bundle);
        }
    }

    /** Follow {@code Bundle.link[rel=next].url} for paging. */
    static String nextLink(JsonNode bundle) {
        if (bundle == null) {
            return null;
        }
        JsonNode links = bundle.get("link");
        if (links != null && links.isArray()) {
            for (JsonNode link : links) {
                JsonNode rel = link.get("relation");
                JsonNode url = link.get("url");
                if (rel != null && "next".equals(rel.asText()) && url != null && url.isTextual()) {
                    return url.asText();
                }
            }
        }
        return null;
    }
}
