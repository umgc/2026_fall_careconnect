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
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_FETCH", resourceType,
                    resourceType, out.isEmpty()
                            ? EhrAuditEvent.OUTCOME_EMPTY : EhrAuditEvent.OUTCOME_OK);
            return out;
        } catch (RuntimeException ex) {
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_FETCH", resourceType,
                    resourceType, EhrAuditEvent.OUTCOME_ERROR);
            throw ex;
        }
    }

    @Override
    public JsonNode everything(Long userId) {
        String token = oauth.validAccessToken(userId);
        String patientId = oauth.patientFhirId(userId);
        HttpEntity<Void> entity = new HttpEntity<>(bearerHeaders(token));
        String url = cfg.getFhirBaseUrl() + "/Patient/" + patientId + "/$everything";
        try {
            ResponseEntity<JsonNode> resp = http.exchange(url, HttpMethod.GET, entity, JsonNode.class);
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_EVERYTHING", "Patient",
                    "$everything", EhrAuditEvent.OUTCOME_OK);
            return resp.getBody();
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
