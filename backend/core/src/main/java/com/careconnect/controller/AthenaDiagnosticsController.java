package com.careconnect.controller;

import com.careconnect.config.AthenaProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.service.ehr.athena.AthenaTokenProvider;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * DIAGNOSTIC ONLY. Proves the 2-legged chain end to end through the running application:
 * authenticated CareConnect user -> cached athena token -> FHIR Patient search -> exact-match
 * verification. It is not the read API; that belongs to the data branch, which will own
 * resource listing, DTOs, paging and the identity crosswalk.
 *
 * <p>Gated on BOTH {@code careconnect.athena.enabled} and
 * {@code careconnect.athena.diagnostics-enabled} (both default false): it injects
 * {@link AthenaTokenProvider}, which only exists when athena is enabled, so requiring one flag
 * alone would fail context startup on a missing bean. Disabled means the route 404s, not 403s.
 *
 * <p>Deliberately returns no raw upstream error bodies: an athena {@code OperationOutcome} can
 * carry identifiers, so failures are reported as a code plus a correlation id and the detail
 * is logged server-side.
 */
@Slf4j
@RestController
@RequestMapping("/api/athena/diag")
@RequiredArgsConstructor
@ConditionalOnProperty(
        name = {"careconnect.athena.enabled", "careconnect.athena.diagnostics-enabled"},
        havingValue = "true")
public class AthenaDiagnosticsController {

    private final SecurityUtil securityUtil;
    private final PatientRepository patientRepository;
    private final AthenaTokenProvider tokens;
    private final AthenaProperties cfg;
    private final RestTemplate http;

    /**
     * Resolve the signed-in CareConnect patient to their athenahealth chart and return it.
     *
     * <p>Self-access only: the patient is taken from the JWT, never from a request parameter,
     * so this cannot be pointed at someone else's record.
     */
    @GetMapping("/my-patient")
    public ResponseEntity<Map<String, Object>> myPatient() {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        final Optional<Patient> local = patientRepository.findByUserId(me.getId());
        if (local.isEmpty()) {
            return ResponseEntity.ok(state("NO_LOCAL_PATIENT",
                    "This user has no patient profile to match on."));
        }
        final Patient p = local.get();
        if (isBlank(p.getFirstName()) || isBlank(p.getLastName())) {
            return ResponseEntity.ok(state("INCOMPLETE_LOCAL_PATIENT",
                    "First and last name are required to resolve an athena chart."));
        }

        final Map<String, Object> body = new HashMap<>();
        body.put("careconnectUser", me.getEmail());
        body.put("searchedFor", Map.of(
                "family", p.getLastName(), "given", p.getFirstName(),
                "dob", p.getDob() == null ? "" : p.getDob()));
        body.put("grantedScopes", tokens.grantedScopes());

        final JsonNode bundle;
        try {
            bundle = searchPatient(p.getLastName(), p.getFirstName());
        } catch (RestClientResponseException ex) {
            final String errorId = UUID.randomUUID().toString();
            log.warn("athena Patient search failed [{}] for user {} -> {} : {}",
                    errorId, me.getId(), ex.getStatusCode().value(), ex.getResponseBodyAsString());
            body.putAll(state(ex.getStatusCode().value() == 403 ? "SCOPE_DENIED" : "SOURCE_UNAVAILABLE",
                    "The data is unreachable at this time."));
            body.put("errorId", errorId);
            return ResponseEntity.ok(body);
        } catch (RuntimeException ex) {
            final String errorId = UUID.randomUUID().toString();
            log.warn("athena Patient search failed [{}] for user {}", errorId, me.getId(), ex);
            body.putAll(state("SOURCE_UNAVAILABLE", "The data is unreachable at this time."));
            body.put("errorId", errorId);
            return ResponseEntity.ok(body);
        }

        // athena reports an over-broad query as HTTP 200 with a fatal OperationOutcome INSIDE
        // Bundle.entry, so entries must be filtered on search.mode before anything is trusted.
        final String fatal = fatalOutcome(bundle);
        if (fatal != null) {
            body.putAll(state("SEARCH_REJECTED", "athena rejected the search: " + fatal));
            return ResponseEntity.ok(body);
        }

        final List<JsonNode> candidates = resources(bundle);
        body.put("candidatesReturned", candidates.size());

        // FHIR string search is PREFIX matching (family=Smith also returns Smitham), so a
        // single-result bundle is not proof of a correct match. Re-verify equality.
        final List<JsonNode> exact = new ArrayList<>();
        for (final JsonNode r : candidates) {
            if (namesMatchExactly(r, p.getLastName(), p.getFirstName())
                    && dobMatches(r, p.getDob())) {
                exact.add(r);
            }
        }
        body.put("exactMatches", exact.size());

        if (exact.isEmpty()) {
            body.putAll(state("NOT_MATCHED", "No athena chart matched this patient exactly."));
        } else if (exact.size() > 1) {
            body.putAll(state("AMBIGUOUS",
                    "More than one athena chart matched; needs identity reconciliation."));
            body.put("athenaPatientIds", exact.stream().map(r -> text(r, "id")).toList());
        } else {
            final JsonNode match = exact.get(0);
            body.putAll(state("MATCHED", "Resolved to a single athena chart."));
            body.put("athenaPatientId", text(match, "id"));
            body.put("resource", match);
        }
        return ResponseEntity.ok(body);
    }

    private JsonNode searchPatient(final String family, final String given) {
        final String url = UriComponentsBuilder.fromHttpUrl(cfg.getFhirBaseUrl() + "/Patient")
                // ah-practice is required on EVERY athena FHIR call, as a search parameter.
                .queryParam("ah-practice", cfg.getPracticeId())
                // [family, given] is one of athena's permitted required-parameter combinations;
                // family alone is a 403.
                .queryParam("family", family)
                .queryParam("given", given)
                .queryParam("_count", 10)
                .build()
                .encode()
                .toUriString();

        final HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(tokens.accessToken());
        h.setAccept(List.of(MediaType.valueOf("application/fhir+json"), MediaType.APPLICATION_JSON));
        return http.exchange(url, HttpMethod.GET, new HttpEntity<>(h), JsonNode.class).getBody();
    }

    /** Bundle.entry[] resources, excluding OperationOutcome entries. */
    private static List<JsonNode> resources(final JsonNode bundle) {
        final List<JsonNode> out = new ArrayList<>();
        if (bundle == null) {
            return out;
        }
        final JsonNode entries = bundle.get("entry");
        if (entries == null || !entries.isArray()) {
            return out;
        }
        for (final JsonNode e : entries) {
            final JsonNode mode = e.path("search").path("mode");
            if (mode.isTextual() && "outcome".equals(mode.asText())) {
                continue;
            }
            final JsonNode r = e.get("resource");
            if (r != null && !r.isNull()) {
                out.add(r);
            }
        }
        return out;
    }

    /** The detail text of a fatal OperationOutcome carried inside a 200 response, if any. */
    private static String fatalOutcome(final JsonNode bundle) {
        if (bundle == null) {
            return null;
        }
        final JsonNode entries = bundle.get("entry");
        if (entries == null || !entries.isArray()) {
            return null;
        }
        for (final JsonNode e : entries) {
            if (!"outcome".equals(e.path("search").path("mode").asText())) {
                continue;
            }
            final JsonNode issue = e.path("resource").path("issue").path(0);
            if ("fatal".equals(issue.path("severity").asText())) {
                final JsonNode details = issue.path("details");
                return details.path("text").isTextual() ? details.path("text").asText()
                        : issue.path("code").asText("unknown");
            }
        }
        return null;
    }

    private static boolean namesMatchExactly(final JsonNode r, final String family, final String given) {
        final JsonNode names = r.get("name");
        if (names == null || !names.isArray()) {
            return false;
        }
        for (final JsonNode n : names) {
            final boolean familyOk = family.equalsIgnoreCase(n.path("family").asText(""));
            boolean givenOk = false;
            for (final JsonNode g : n.path("given")) {
                if (given.equalsIgnoreCase(g.asText(""))) {
                    givenOk = true;
                    break;
                }
            }
            if (familyOk && givenOk) {
                return true;
            }
        }
        return false;
    }

    /** A blank local DOB does not veto the match; a present one must agree. */
    private static boolean dobMatches(final JsonNode r, final String localDob) {
        if (isBlank(localDob)) {
            return true;
        }
        return localDob.trim().equals(r.path("birthDate").asText(""));
    }

    private static Map<String, Object> state(final String code, final String message) {
        final Map<String, Object> m = new HashMap<>();
        m.put("state", code);
        m.put("message", message);
        return m;
    }

    private static String text(final JsonNode n, final String field) {
        return n.path(field).asText(null);
    }

    private static boolean isBlank(final String s) {
        return s == null || s.isBlank();
    }
}
