package com.careconnect.service;

import ca.uhn.fhir.context.FhirContext;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.CapabilityStatement;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.Enumerations;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.hl7.fhir.r4.model.Resource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.*;

/**
 * WBS 3.6.4 Performance and reliability verification (M3), FHIR retrieval part.
 * Verifies {@link FHIRService} against STP-M3-E-01 (pagination), STP-M3-E-02
 * (partial failure) and STP-M3-E-03 (backoff) using a local stand-in for the
 * Blue Button FHIR server, so no network or CMS credentials are needed.
 *
 * <p>Tests named {@code finding_*} pin behaviour that does NOT meet the STP
 * requirement today. They pass so the build stays green, and each one is listed
 * as a defect in docs/verification/3.6.4-fhir-retrieval-reliability.md. When the
 * code is fixed, the matching test must be flipped to assert the requirement.
 *
 * <p>Test IDs (VER-FHIR-xx) match the verification report.
 */
class FHIRServiceReliabilityVerificationTest {

    private static final FhirContext CTX = FhirContext.forR4();
    private static final String TOKEN = "test-token-not-a-secret";

    private HttpServer server;
    private String base;
    private final Map<String, Integer> hits = new ConcurrentHashMap<>();
    private final List<String> authHeaders = Collections.synchronizedList(new ArrayList<>());
    private final List<String> queries = Collections.synchronizedList(new ArrayList<>());
    /** path + "?" + query -> response; unmatched requests get 404. */
    private final Map<String, Function<HttpExchange, Reply>> routes = new ConcurrentHashMap<>();

    private record Reply(int status, String body) {}

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/fhir/", this::handle);
        server.start();
        base = "http://127.0.0.1:" + server.getAddress().getPort() + "/fhir/";
        CapabilityStatement cs = new CapabilityStatement();
        cs.setFhirVersion(Enumerations.FHIRVersion._4_0_1);
        routes.put("metadata", ex -> new Reply(200, json(cs)));
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    private void handle(HttpExchange ex) throws IOException {
        String path = ex.getRequestURI().getPath().substring("/fhir/".length());
        String query = ex.getRequestURI().getRawQuery();
        String key = path + (query == null ? "" : "?" + query);
        if (!"metadata".equals(path)) {
            hits.merge(path, 1, Integer::sum);
            authHeaders.add(ex.getRequestHeaders().getFirst("Authorization"));
            queries.add(query == null ? "" : java.net.URLDecoder.decode(query, StandardCharsets.UTF_8));
        }
        Function<HttpExchange, Reply> route = routes.getOrDefault(key, routes.get(path));
        Reply r = route == null ? new Reply(404, "{}") : route.apply(ex);
        byte[] bytes = r.body().getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().add("Content-Type", "application/fhir+json");
        ex.sendResponseHeaders(r.status(), bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }

    private static String json(Resource r) {
        return CTX.newJsonParser().encodeResourceToString(r);
    }

    /** A searchset page with the given resources, an optional total and an optional next link. */
    private static Bundle page(List<? extends Resource> resources, Integer total, String next) {
        Bundle b = new Bundle();
        b.setType(Bundle.BundleType.SEARCHSET);
        if (total != null) b.setTotal(total);
        for (Resource r : resources) b.addEntry().setResource(r);
        if (next != null) b.addLink().setRelation(Bundle.LINK_NEXT).setUrl(next);
        return b;
    }

    private static List<Coverage> coverages(String prefix, int n) {
        List<Coverage> out = new ArrayList<>();
        for (int i = 1; i <= n; i++) {
            Coverage c = new Coverage();
            c.setId(prefix + i);
            out.add(c);
        }
        return out;
    }

    private static List<ExplanationOfBenefit> eobs(String prefix, int n) {
        List<ExplanationOfBenefit> out = new ArrayList<>();
        for (int i = 1; i <= n; i++) {
            ExplanationOfBenefit e = new ExplanationOfBenefit();
            e.setId(prefix + i);
            out.add(e);
        }
        return out;
    }

    private FHIRService service() {
        return new FHIRService(base);
    }

    private static List<String> ids(List<? extends Resource> rs) {
        return rs.stream().map(r -> r.getIdElement().getIdPart()).collect(Collectors.toList());
    }

    // ---- STP-M3-E-01 Pagination --------------------------------------------------------------

    @Test
    @DisplayName("VER-FHIR-01 Coverage retrieval follows every next link across 3 pages with no duplicates")
    void coverageFollowsAllPages() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 5, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(coverages("d", 2), 5, base + "Coverage?page=3"))));
        routes.put("Coverage?page=3", ex -> new Reply(200, json(page(coverages("e", 1), 5, null))));

        List<Coverage> result = service().requestMedicareCoverageInfo(TOKEN);

        assertEquals(List.of("c1", "c2", "d1", "d2", "e1"), ids(result));
        assertEquals(3, hits.get("Coverage"), "one request per page");
    }

    @Test
    @DisplayName("VER-FHIR-02 EOB retrieval follows every next link across 3 pages")
    void eobFollowsAllPages() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 3), 7, base + "ExplanationOfBenefit?page=2"))));
        routes.put("ExplanationOfBenefit?page=2", ex -> new Reply(200, json(page(eobs("b", 3), 7, base + "ExplanationOfBenefit?page=3"))));
        routes.put("ExplanationOfBenefit?page=3", ex -> new Reply(200, json(page(eobs("c", 1), 7, null))));

        List<ExplanationOfBenefit> result = service().requestMedicareEOBInfo(TOKEN);

        assertEquals(7, result.size());
        assertEquals(7, result.stream().map(e -> e.getIdElement().getIdPart()).distinct().count(), "no duplicates");
    }

    @Test
    @DisplayName("VER-FHIR-03 An empty search result returns an empty list, not an error")
    void emptyResultIsEmptyList() {
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(), 0, null))));
        assertTrue(service().requestMedicareCoverageInfo(TOKEN).isEmpty());
    }

    @Test
    @DisplayName("VER-FHIR-04 Every request carries the patient's bearer token")
    void bearerTokenOnEveryRequest() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 1), 2, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(coverages("d", 1), 2, null))));

        service().requestMedicareCoverageInfo(TOKEN);

        assertEquals(2, authHeaders.size());
        assertTrue(authHeaders.stream().allMatch(("Bearer " + TOKEN)::equals));
    }

    @Test
    @DisplayName("VER-FHIR-05 An incremental sync sends _lastUpdated=ge<date>")
    void incrementalSyncSendsLastUpdated() {
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(), 0, null))));
        Date since = Date.from(Instant.parse("2026-09-01T00:00:00Z"));

        service().requestMedicareCoverageInfo(TOKEN, since);

        // The date is sent in the JVM's local offset, so compare the instant, not the text.
        String q = queries.get(0);
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("_lastUpdated=ge([^&]+)").matcher(q);
        assertTrue(m.find(), q);
        assertEquals(since.toInstant(), java.time.OffsetDateTime.parse(m.group(1)).toInstant(), q);
    }

    @Test
    @DisplayName("VER-FHIR-06 Patient lookup returns the single Patient, and refuses zero or several")
    void patientLookup() {
        Patient p = new Patient();
        p.setId("p1");
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(p), 1, null))));
        assertEquals("p1", service().requestMedicarePatientInfo(TOKEN).getIdElement().getIdPart());

        Patient q = new Patient();
        q.setId("p2");
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(p, q), 2, null))));
        RuntimeException e = assertThrows(RuntimeException.class, () -> service().requestMedicarePatientInfo(TOKEN));
        assertTrue(e.getMessage().contains("quantity"), e.getMessage());
    }

    @Test
    @DisplayName("VER-FHIR-07 A wrong resource type in a Coverage search is rejected")
    void wrongResourceTypeRejected() {
        routes.put("Coverage", ex -> new Reply(200, json(page(eobs("x", 1), 1, null))));
        assertThrows(RuntimeException.class, () -> service().requestMedicareCoverageInfo(TOKEN));
    }

    // ---- Findings: behaviour that does not meet the STP today ----------------------------------

    @Test
    @DisplayName("VER-FHIR-08 Finding (STP-M3-E-02): a failed page discards the pages already retrieved")
    void finding_failedPageDiscardsEarlierPages() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 4, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(500, "{}"));

        // STP-M3-E-02 requires the retrieved pages to be kept and the failure reported. Today the
        // exception propagates and the caller receives nothing, so page 1's two records are lost.
        assertThrows(Exception.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertEquals(2, hits.get("Coverage"), "page 1 was fetched, then lost");
    }

    @Test
    @DisplayName("VER-FHIR-09 Finding (STP-M3-E-03): a 429 or 503 is not retried")
    void finding_rateLimitIsNotRetried() {
        routes.put("Coverage", ex -> new Reply(429, "{}"));
        assertThrows(Exception.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertEquals(1, hits.get("Coverage"), "exactly one attempt: no retry and no backoff");

        hits.clear();
        routes.put("Coverage", ex -> new Reply(503, "{}"));
        assertThrows(Exception.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertEquals(1, hits.get("Coverage"));
    }

    @Test
    @DisplayName("VER-FHIR-10 Finding: a page with entries but no Bundle.total returns nothing")
    void finding_missingTotalDropsEntries() {
        // Bundle.total is optional in FHIR search results (0..1). The service checks getTotal() == 0
        // before reading entries, so records the server did send are silently dropped.
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 3), null, null))));

        List<Coverage> result = service().requestMedicareCoverageInfo(TOKEN);

        assertTrue(result.isEmpty(), "3 records were sent but none are returned");
    }
}
